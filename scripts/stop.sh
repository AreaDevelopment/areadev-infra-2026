#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# stop.sh — Stop the full AreaDevelopment stack
#   Stops in reverse order: Frontend → API → Directus → Infra
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$(dirname "$PROJECT_ROOT")"

DIRECTUS_DIR="$PROJECTS_DIR/areadev-directus-cms-v1"

PIDS_DIR="$PROJECT_ROOT/.pids"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_step()  { echo -e "${BLUE}── $* ──${NC}"; }

# ─────────────────────────────────────────────────────────────
# Stop a background process by PID file
# ─────────────────────────────────────────────────────────────
stop_pid() {
  local name="$1"
  local pidfile="$PIDS_DIR/$name.pid"

  if [[ -f "$pidfile" ]]; then
    local pid
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      # Wait for graceful shutdown
      local i=0
      while kill -0 "$pid" 2>/dev/null && (( i < 10 )); do
        sleep 0.5
        i=$((i + 1))
      done
      # Force kill if still running
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
      fi
      log_ok "$name stopped (pid $pid)"
    else
      log_info "$name not running (stale pid $pid)"
    fi
    rm -f "$pidfile"
  else
    log_info "$name — no pid file found"
  fi
}

main() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE} areadev-infra-2026 — Stopping Full Stack${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  log_step "Frontend (Nuxt)"
  stop_pid "frontend"

  log_step "API Server"
  stop_pid "api"

  log_step "Directus CMS"
  if [[ -d "$DIRECTUS_DIR" ]]; then
    cd "$DIRECTUS_DIR"
    docker compose stop 2>/dev/null && log_ok "Directus stopped" || log_info "Directus was not running"
  else
    log_info "Directus directory not found"
  fi

  log_step "Infrastructure Services"
  cd "$PROJECT_ROOT"
  docker compose stop
  log_ok "Infrastructure services stopped"

  echo ""
  log_ok "Full stack stopped. Data volumes are preserved."
  log_info "Use 'scripts/nuke.sh' to destroy all data."
}

main "$@"
