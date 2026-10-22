#!/bin/bash
# Setup git hooks for automatic local CI/CD

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
DEPLOY_SCRIPT="$REPO_ROOT/scripts/deploy-local.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Setting up git hooks for local CI/CD${NC}"

# Check if we're in a git repository
if [[ ! -d "$REPO_ROOT/.git" ]]; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Ensure hooks directory exists
mkdir -p "$HOOKS_DIR"

# Make deploy script executable
chmod +x "$DEPLOY_SCRIPT"

# Create post-commit hook
cat > "$HOOKS_DIR/post-commit" << 'HOOK_EOF'
#!/bin/bash
# Post-commit hook: Deploy changes automatically

# Skip if SKIP_LOCAL_DEPLOY is set
if [[ "${SKIP_LOCAL_DEPLOY:-}" == "1" ]]; then
    exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
DEPLOY_SCRIPT="$REPO_ROOT/scripts/deploy-local.sh"

# Check if deploy script exists
if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    exit 0
fi

# Get list of changed files in this commit
CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD)

# Check if any relevant files changed
RELEVANT_CHANGES=false
if echo "$CHANGED_FILES" | grep -qE "^stacks/|^ansible/deploy-"; then
    RELEVANT_CHANGES=true
fi

if [[ "$RELEVANT_CHANGES" == "true" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🚀 Detected deployment changes - Starting auto-deploy"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Run deployment in background (non-blocking)
    "$DEPLOY_SCRIPT" > /tmp/git-hook-deploy.log 2>&1 &
    DEPLOY_PID=$!
    
    echo "Deployment started in background (PID: $DEPLOY_PID)"
    echo "View logs: tail -f /tmp/git-hook-deploy.log"
    echo "Or check: $REPO_ROOT/logs/deploy-*.log"
    echo ""
fi

exit 0
HOOK_EOF

# Create post-merge hook
cat > "$HOOKS_DIR/post-merge" << 'HOOK_EOF'
#!/bin/bash
# Post-merge hook: Deploy changes after pull/merge

# Skip if SKIP_LOCAL_DEPLOY is set
if [[ "${SKIP_LOCAL_DEPLOY:-}" == "1" ]]; then
    exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
DEPLOY_SCRIPT="$REPO_ROOT/scripts/deploy-local.sh"

# Check if deploy script exists
if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    exit 0
fi

# Get list of changed files in the merge
CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD)

# Check if any relevant files changed
RELEVANT_CHANGES=false
if echo "$CHANGED_FILES" | grep -qE "^stacks/|^ansible/deploy-"; then
    RELEVANT_CHANGES=true
fi

if [[ "$RELEVANT_CHANGES" == "true" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🚀 Detected deployment changes after merge - Starting auto-deploy"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Run deployment in background (non-blocking)
    "$DEPLOY_SCRIPT" > /tmp/git-hook-deploy.log 2>&1 &
    DEPLOY_PID=$!
    
    echo "Deployment started in background (PID: $DEPLOY_PID)"
    echo "View logs: tail -f /tmp/git-hook-deploy.log"
    echo "Or check: $REPO_ROOT/logs/deploy-*.log"
    echo ""
fi

exit 0
HOOK_EOF

# Make hooks executable
chmod +x "$HOOKS_DIR/post-commit"
chmod +x "$HOOKS_DIR/post-merge"

echo -e "${GREEN}✓ Git hooks installed successfully${NC}"
echo ""
echo "Hooks created:"
echo "  - .git/hooks/post-commit  (runs after git commit)"
echo "  - .git/hooks/post-merge   (runs after git pull/merge)"
echo ""
echo -e "${YELLOW}Note:${NC} Set SKIP_LOCAL_DEPLOY=1 to bypass auto-deployment"
echo "Example: SKIP_LOCAL_DEPLOY=1 git commit -m 'WIP: not ready to deploy'"
echo ""
