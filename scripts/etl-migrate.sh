#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# etl-migrate.sh — Run a full ETL migration (wipe + re-import)
#
# Executes: authors → topics → issues → states → articles
# Requires: PostGIS and MSSQL to be running and healthy
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$(dirname "$PROJECT_ROOT")"

ETL_DIR="$PROJECTS_DIR/areadev-etl-2024"
LOGS_DIR="$PROJECT_ROOT/.logs"
mkdir -p "$LOGS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo ""; echo -e "${BLUE}── $* ──${NC}"; }

# ─────────────────────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────────────────────
preflight() {
  if [[ ! -d "$ETL_DIR" ]]; then
    log_err "areadev-etl-2024 not found at $ETL_DIR"
    exit 1
  fi

  for container in infra-postgis infra-mssql; do
    local health
    health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")
    if [[ "$health" != "healthy" ]]; then
      log_err "$container is not healthy (status: $health). Run scripts/start.sh first."
      exit 1
    fi
  done

  log_ok "Pre-flight checks passed"
}

# ─────────────────────────────────────────────────────────────
# Run full migration
# ─────────────────────────────────────────────────────────────
run_migrate() {
  log_step "Full ETL Migration"
  log_info "Running: pnpm migrate (authors → topics → issues → states → articles)"
  log_info "This wipes target tables and re-imports all data from MSSQL"

  cd "$ETL_DIR"

  local start=$SECONDS
  if pnpm migrate 2>&1 | tee "$LOGS_DIR/etl-migrate.log"; then
    local duration=$(( SECONDS - start ))
    log_ok "Full migration completed in ${duration}s"
  else
    local duration=$(( SECONDS - start ))
    log_err "Migration failed after ${duration}s (see .logs/etl-migrate.log)"
    exit 1
  fi
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
main() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE} areadev-infra-2026 — Full ETL Migration${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  preflight
  run_migrate

  echo ""
  log_ok "Migration complete. Review output above or check .logs/etl-migrate.log"
}

main "$@"
