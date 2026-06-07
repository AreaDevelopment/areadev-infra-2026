#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# submodules.sh — Initialize/update git submodules in all projects
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$(dirname "$PROJECT_ROOT")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE} Git Submodule Initialization${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Find all sibling project directories with .gitmodules
found=0
for dir in "$PROJECTS_DIR"/areadev-*/; do
  if [[ -f "$dir/.gitmodules" ]]; then
    found=$((found + 1))
    project_name=$(basename "$dir")
    log_info "Updating submodules in $project_name..."

    (
      cd "$dir"
      git submodule update --init --recursive 2>/dev/null && \
        log_ok "$project_name submodules up to date" || \
        log_warn "$project_name submodule update had issues"
    )
  fi
done

if [[ $found -eq 0 ]]; then
  log_info "No projects with .gitmodules found."
else
  echo ""
  log_ok "Processed $found project(s) with submodules."
fi
