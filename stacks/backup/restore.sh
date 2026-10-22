#!/usr/bin/env bash
set -euo pipefail

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/repo}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  list                          Show all snapshots
  restore-volume <name> [snap]  Restore a specific Docker volume (default: latest)
  restore-env [snap]            Restore the env file (default: latest)
  restore-all [snap]            Full restore to /restore (default: latest)
EOF
  exit 1
}

[ $# -lt 1 ] && usage

COMMAND="$1"
shift

case "${COMMAND}" in
  list)
    restic snapshots --tag docker-backup
    ;;

  restore-volume)
    [ $# -lt 1 ] && { echo "Error: volume name required"; usage; }
    VOLUME_NAME="$1"
    SNAPSHOT="${2:-latest}"
    echo "Restoring volume '${VOLUME_NAME}' from snapshot ${SNAPSHOT}..."
    restic restore "${SNAPSHOT}" \
      --include "/volumes/${VOLUME_NAME}" \
      --target /
    echo "Volume '${VOLUME_NAME}' restored."
    ;;

  restore-env)
    SNAPSHOT="${1:-latest}"
    echo "Restoring env file from snapshot ${SNAPSHOT}..."
    restic restore "${SNAPSHOT}" \
      --include "/env-file" \
      --target /
    echo "Env file restored to /env-file/"
    ;;

  restore-all)
    SNAPSHOT="${1:-latest}"
    echo "Restoring everything from snapshot ${SNAPSHOT} to /restore..."
    mkdir -p /restore
    restic restore "${SNAPSHOT}" \
      --target /restore
    echo "Full restore complete at /restore/"
    ;;

  *)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac
