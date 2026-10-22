#!/bin/bash
# Local CI/CD deployment script
# Automatically detects changed stacks and deploys via Ansible
# Features: Animated dinosaur during deployment! 🦖

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible"
LOGS_DIR="$REPO_ROOT/logs"

# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

# Log file with timestamp
LOG_FILE="$LOGS_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"

# Function to log messages
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Animated dinosaur while deployment runs
show_dinosaur() {
    local pid=$1
    local frames=(
        "🦖"
        "🦕"
        "🦖"
        "🦕"
    )
    local messages=(
        "Running Ansible playbooks..."
        "Deploying containers..."
        "Configuring services..."
        "Almost done..."
    )
    local i=0
    local frame_count=0
    
    while kill -0 "$pid" 2>/dev/null; do
        local frame="${frames[$i]}"
        local msg="${messages[$i]}"
        
        # Clear line and show dinosaur
        printf "\r${GREEN}%s${NC} %s ${YELLOW}%s${NC}" "$frame" "$msg" "$(date +%H:%M:%S)"
        
        i=$(( (i+1) % ${#frames[@]} ))
        frame_count=$((frame_count + 1))
        
        # Change message every 4 frames
        if [[ $((frame_count % 4)) -eq 0 ]]; then
            i=$(( (i+1) % ${#frames[@]} ))
        fi
        
        sleep 0.6
    done
    
    # Clear the line
    printf "\r${NC}"
    printf "                                                                                \r"
}

# Parse command line arguments
DRY_RUN=false
VERBOSE=false
FORCE_STACKS=""
SKIP_K3S=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --stacks)
            FORCE_STACKS="$2"
            shift 2
            ;;
        --skip-k3s)
            SKIP_K3S=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run          Show what would be deployed without actually deploying"
            echo "  --verbose, -v      Enable verbose output"
            echo "  --stacks STACKS    Deploy specific stacks (comma-separated: core,media,database,networking,gitea,notes,projects,ai-tools,openclaw)"
            echo "  --skip-k3s         Skip K3s deployments even if gitops/ changed"
            echo "  --help, -h         Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if Ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    log_error "Ansible is not installed. Please install it first:"
    echo "  brew install ansible"
    exit 1
fi

# Check if inventory file exists
INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"
if [[ ! -f "$INVENTORY_FILE" ]]; then
    log_error "Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

# Function to detect changed stacks from git
detect_changed_stacks() {
    local changed_stacks=""
    
    # Get list of changed files
    local changed_files
    if git rev-parse --verify HEAD~1 &> /dev/null; then
        changed_files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
    else
        # First commit, check all files
        changed_files=$(git ls-files 2>/dev/null || echo "")
    fi
    
    # Check for stack changes
    for stack in core media database networking gitea notes projects ai-tools openclaw; do
        if echo "$changed_files" | grep -q "^stacks/${stack}/"; then
            changed_stacks="${changed_stacks}${stack},"
        fi
    done
    
    # Check for Ansible deployment playbook changes
    if echo "$changed_files" | grep -q "^ansible/deploy-stacks.yml"; then
        # If deploy script changed, deploy all stacks
        if [[ -z "$changed_stacks" ]]; then
            changed_stacks="core,media,database,networking,gitea,notes,projects,ai-tools,openclaw,"
        fi
    fi
    
    # Remove trailing comma
    changed_stacks=${changed_stacks%,}
    echo "$changed_stacks"
}

# Function to detect K3s changes
detect_k3s_changes() {
    local changed_files
    if git rev-parse --verify HEAD~1 &> /dev/null; then
        changed_files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
    else
        changed_files=$(git ls-files 2>/dev/null || echo "")
    fi
    
    # Check for K3s changes - gitops is now at /Users/bp31/Documents/gitops
    # We can't detect changes there via git, so we'll check ansible deploy scripts
    if echo "$changed_files" | grep -q "^ansible/deploy-k3s"; then
        echo "true"
    else
        echo "false"
    fi
}

# Main deployment function
deploy_stacks() {
    local stacks="$1"
    
    if [[ -z "$stacks" ]]; then
        log_warning "No stacks to deploy"
        return 0
    fi
    
    log "Deploying stacks: $stacks"
    
    # Convert comma-separated to JSON array
    local json_stacks
    if command -v jq &> /dev/null; then
        json_stacks=$(echo "$stacks" | tr ',' '\n' | jq -R . | jq -s . 2>/dev/null || echo "[\"$stacks\"]")
    else
        # Fallback: create JSON array manually
        local stack_array=""
        IFS=',' read -ra STACK_ARRAY <<< "$stacks"
        for stack in "${STACK_ARRAY[@]}"; do
            stack_array="${stack_array}\"${stack}\","
        done
        stack_array=${stack_array%,}
        json_stacks="[${stack_array}]"
    fi
    
    local ansible_cmd="ansible-playbook -i $INVENTORY_FILE $ANSIBLE_DIR/deploy-stacks.yml"
    ansible_cmd="$ansible_cmd --extra-vars '{\"stacks_to_deploy\": $json_stacks}'"
    
    if [[ "$VERBOSE" == "true" ]]; then
        ansible_cmd="$ansible_cmd -v"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN - Would execute: $ansible_cmd"
        return 0
    fi
    
    log "Running: $ansible_cmd"
    
    # Run Ansible in background and show animation
    eval "$ansible_cmd" >> "$LOG_FILE" 2>&1 &
    local ansible_pid=$!
    
    # Show dinosaur animation while deploying
    show_dinosaur "$ansible_pid" &
    local anim_pid=$!
    
    # Wait for Ansible to complete
    wait $ansible_pid
    local ansible_exit=$?
    
    # Stop animation
    kill $anim_pid 2>/dev/null
    wait $anim_pid 2>/dev/null
    
    # Show final output
    if [[ $ansible_exit -eq 0 ]]; then
        log_success "Stacks deployed successfully: $stacks"
        # Show last few lines of output
        tail -20 "$LOG_FILE" | grep -E "(changed|ok|failed|unreachable)" | tail -5 || true
        return 0
    else
        log_error "Deployment failed for stacks: $stacks"
        echo ""
        echo "${RED}Last 10 lines of output:${NC}"
        tail -10 "$LOG_FILE"
        return 1
    fi
}

# K3s deployment function
deploy_k3s() {
    if [[ "$SKIP_K3S" == "true" ]]; then
        log "Skipping K3s deployment (--skip-k3s flag set)"
        return 0
    fi
    
    log "Deploying K3s components (Traefik)"
    
    local ansible_cmd="ansible-playbook -i $INVENTORY_FILE $ANSIBLE_DIR/deploy-k3s-traefik.yml"
    
    if [[ "$VERBOSE" == "true" ]]; then
        ansible_cmd="$ansible_cmd -v"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN - Would execute: $ansible_cmd"
        return 0
    fi
    
    log "Running: $ansible_cmd"
    
    # Run Ansible in background and show animation
    eval "$ansible_cmd" >> "$LOG_FILE" 2>&1 &
    local ansible_pid=$!
    
    # Show dinosaur animation while deploying
    show_dinosaur "$ansible_pid" &
    local anim_pid=$!
    
    # Wait for Ansible to complete
    wait $ansible_pid
    local ansible_exit=$?
    
    # Stop animation
    kill $anim_pid 2>/dev/null
    wait $anim_pid 2>/dev/null
    
    # Show final output
    if [[ $ansible_exit -eq 0 ]]; then
        log_success "K3s deployment completed successfully"
        tail -20 "$LOG_FILE" | grep -E "(changed|ok|failed|unreachable)" | tail -5 || true
        return 0
    else
        log_error "K3s deployment failed"
        echo ""
        echo "${RED}Last 10 lines of output:${NC}"
        tail -10 "$LOG_FILE"
        return 1
    fi
}

# Main execution
main() {
    log "Starting local deployment"
    log "Log file: $LOG_FILE"
    
    cd "$REPO_ROOT"
    
    # Determine what to deploy
    local stacks_to_deploy=""
    local deploy_k3s_flag=false
    
    if [[ -n "$FORCE_STACKS" ]]; then
        stacks_to_deploy="$FORCE_STACKS"
        log "Using forced stacks: $stacks_to_deploy"
    else
        stacks_to_deploy=$(detect_changed_stacks)
        if [[ -n "$stacks_to_deploy" ]]; then
            log "Detected changed stacks: $stacks_to_deploy"
        fi
    fi
    
    # Check for K3s changes
    if [[ "$(detect_k3s_changes)" == "true" ]]; then
        deploy_k3s_flag=true
        log "Detected K3s/gitops changes"
    fi
    
    # Deploy stacks
    local exit_code=0
    if [[ -n "$stacks_to_deploy" ]]; then
        if ! deploy_stacks "$stacks_to_deploy"; then
            exit_code=1
        fi
    else
        log "No stack changes detected"
    fi
    
    # Deploy K3s if needed
    if [[ "$deploy_k3s_flag" == "true" ]]; then
        if ! deploy_k3s; then
            exit_code=1
        fi
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Deployment completed successfully"
    else
        log_error "Deployment completed with errors"
    fi
    
    return $exit_code
}

# Run main function
main "$@"
