#!/usr/bin/env bash
# Targeted audio transcode: convert DTS and FLAC audio to AAC for Jellyfin direct play.
# Video stream is COPIED (no quality loss, no size increase).
# Safe: transcodes to a temp file, atomically replaces original only on success.
#
# Your library breakdown:
#   Video: 645 HEVC + 404 H.264 — both already optimal, NOT touched
#   Audio: 22 DTS + 99 FLAC → these are converted to EAC3/AAC
#
# Usage:
#   ./transcode-media.sh [--dry-run] [path1] [path2] ...
#   Default paths: /mnt/truenas-arr/tv /mnt/truenas-arr/movies
#
# Examples:
#   ./transcode-media.sh --dry-run           # show what would be changed
#   ./transcode-media.sh                     # fix DTS+FLAC audio library-wide
#   ./transcode-media.sh /mnt/truenas-arr/movies   # movies only

set -euo pipefail

PATHS=()
DRY_RUN=false
LOG_FILE="/tmp/transcode-$(date +%Y%m%d-%H%M%S).log"
EXTENSIONS="mkv|mp4|avi|ts|m2ts"

# Audio codecs that cause Jellyfin to transcode on most clients
PROBLEM_AUDIO="dts|flac"

for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    DRY_RUN=true
  else
    PATHS+=("$arg")
  fi
done

if [[ ${#PATHS[@]} -eq 0 ]]; then
  PATHS=("/mnt/truenas-arr/tv" "/mnt/truenas-arr/movies")
fi

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "=== Audio transcode run started ==="
log "Dry run: $DRY_RUN"
log "Log:     $LOG_FILE"
log "Paths:   ${PATHS[*]}"
log "Target:  DTS + FLAC audio → AAC 192k (video streams copied untouched)"

if ! command -v ffmpeg &>/dev/null || ! command -v ffprobe &>/dev/null; then
  log "ERROR: ffmpeg/ffprobe not found"
  exit 1
fi

SKIP=0
DONE=0
FAIL=0
TOTAL=0

process_file() {
  local input="$1"
  local base tmpfile

  base="${input%.*}"
  tmpfile="${base}.transcode_tmp.mkv"

  # Get primary audio codec
  local acodec
  acodec=$(ffprobe -v error -select_streams a:0 \
    -show_entries stream=codec_name -of default=nw=1:nk=1 \
    "$input" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "unknown")

  # Check if audio is a problem codec
  if ! echo "$acodec" | grep -qE "^(${PROBLEM_AUDIO})$"; then
    log "  SKIP  [audio=$acodec] $input"
    ((SKIP++)) || true
    return
  fi

  # Get video codec for logging (always copied)
  local vcodec
  vcodec=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name -of default=nw=1:nk=1 \
    "$input" 2>/dev/null || echo "unknown")

  log "  QUEUE [video=$vcodec COPY, audio=$acodec → aac] $input"

  if [[ "$DRY_RUN" == "true" ]]; then
    return
  fi

  # Transcode: copy all video streams, convert all audio to AAC, copy subtitles
  if ffmpeg -y \
    -i "$input" \
    -c:v copy \
    -c:a aac -b:a 192k \
    -c:s copy \
    -c:t copy \
    -map 0 \
    "$tmpfile" \
    >> "$LOG_FILE" 2>&1; then
    mv "$tmpfile" "${base}.mkv"
    # Remove original if it had a different extension
    if [[ "$input" != "${base}.mkv" ]]; then
      rm -f "$input"
    fi
    log "  DONE  $input"
    ((DONE++)) || true
  else
    rm -f "$tmpfile"
    log "  FAIL  $input (see log for ffmpeg details)"
    ((FAIL++)) || true
  fi
}

for search_path in "${PATHS[@]}"; do
  if [[ ! -d "$search_path" ]]; then
    log "WARNING: path not found: $search_path"
    continue
  fi
  log "Scanning: $search_path"

  while IFS= read -r -d '' file; do
    ((TOTAL++)) || true
    process_file "$file"
  done < <(find "$search_path" -type f -regextype posix-extended \
    -iregex ".*\.(${EXTENSIONS})$" -print0)
done

log ""
log "=== Summary ==="
log "  Total scanned   : $TOTAL"
log "  Skipped (OK)    : $SKIP"
log "  Transcoded      : $DONE"
log "  Failed          : $FAIL"
log "Log saved to: $LOG_FILE"
