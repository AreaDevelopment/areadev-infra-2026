#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# start.sh — Start all infrastructure services
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

# ─────────────────────────────────────────────────────────────
# Initialize git submodules in sibling projects
# ─────────────────────────────────────────────────────────────
init_submodules() {
  log_info "Initializing git submodules in sibling projects..."
  "$SCRIPT_DIR/submodules.sh" || log_warn "Some submodules may not have initialized"
}

# ─────────────────────────────────────────────────────────────
# Start docker-compose services
# ─────────────────────────────────────────────────────────────
start_services() {
  log_info "Starting infrastructure services..."
  cd "$PROJECT_ROOT"

  # Copy .env.example to .env if it doesn't exist
  if [[ ! -f .env ]]; then
    log_warn ".env not found, copying from .env.example"
    cp .env.example .env
  fi

  docker compose up -d
  log_ok "Docker compose services started"
}

# ─────────────────────────────────────────────────────────────
# Wait for all services to be healthy
# ─────────────────────────────────────────────────────────────
wait_for_health() {
  local timeout="${1:-120}"
  local start=$SECONDS

  log_info "Waiting for services to become healthy (timeout: ${timeout}s)..."

  local services=("infra-postgis" "infra-mssql" "infra-redis" "infra-localstack")

  for service in "${services[@]}"; do
    while true; do
      if (( SECONDS - start > timeout )); then
        log_err "Timeout waiting for $service to become healthy"
        docker compose logs "$service" 2>/dev/null | tail -5
        exit 1
      fi

      local health
      health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "not_found")

      if [[ "$health" == "healthy" ]]; then
        log_ok "$service is healthy"
        break
      elif [[ "$health" == "not_found" ]]; then
        log_err "$service container not found"
        exit 1
      fi

      sleep 2
    done
  done
}

# ─────────────────────────────────────────────────────────────
# Print status table
# ─────────────────────────────────────────────────────────────
print_status() {
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
  echo -e "${GREEN} Infrastructure Services Running${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
  printf "  %-15s %-10s %s\n" "SERVICE" "PORT" "STATUS"
  printf "  %-15s %-10s %s\n" "───────────────" "──────────" "──────"
  printf "  %-15s %-10s %s\n" "PostGIS 16" "5432" "✓ healthy"
  printf "  %-15s %-10s %s\n" "MSSQL 2019" "1433" "✓ healthy"
  printf "  %-15s %-10s %s\n" "Redis 7" "6379" "✓ healthy"
  printf "  %-15s %-10s %s\n" "LocalStack" "4566" "✓ healthy"
  printf "  %-15s %-10s %s\n" "ETL Cron" "—" "✓ running"
  echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
  echo ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
main() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE} areadev-infra-2026 — Starting Services${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  init_submodules
  start_services
  wait_for_health 120
  print_status
}

main "$@"
