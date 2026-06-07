#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# rebuild.sh — Destroy everything and rebuild from scratch
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }

main() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE} areadev-infra-2026 — Full Rebuild${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  cd "$PROJECT_ROOT"

  # Nuke everything (skip confirmation)
  log_info "Nuking existing infrastructure..."
  "$SCRIPT_DIR/nuke.sh" --yes

  # Rebuild images
  log_info "Rebuilding Docker images (no cache)..."
  docker compose build --no-cache

  # Start fresh
  log_info "Starting fresh infrastructure..."
  "$SCRIPT_DIR/start.sh"

  log_ok "Full rebuild complete."
}

main "$@"
