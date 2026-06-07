#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# start.sh — Start the full AreaDevelopment stack
#   1. Infrastructure (PostGIS, MSSQL, Redis, LocalStack, ETL cron)
#   2. Directus CMS + push migrations
#   3. API dev server
#   4. Frontend (Nuxt) dev server
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$(dirname "$PROJECT_ROOT")"

DIRECTUS_DIR="$PROJECTS_DIR/areadev-directus-cms-v1"
API_DIR="$PROJECTS_DIR/areadev-api-2025"
FRONTEND_DIR="$PROJECTS_DIR/areadev-frontend-2025"

PIDS_DIR="$PROJECT_ROOT/.pids"
LOGS_DIR="$PROJECT_ROOT/.logs"
mkdir -p "$PIDS_DIR" "$LOGS_DIR"

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
# Initialize git submodules in sibling projects
# ─────────────────────────────────────────────────────────────
init_submodules() {
  log_info "Initializing git submodules in sibling projects..."
  "$SCRIPT_DIR/submodules.sh" || log_warn "Some submodules may not have initialized"
}

# ─────────────────────────────────────────────────────────────
# Start docker-compose infrastructure services
# ─────────────────────────────────────────────────────────────
start_infra() {
  log_step "Infrastructure Services"
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
# Wait for infra services to be healthy
# ─────────────────────────────────────────────────────────────
wait_for_infra() {
  local timeout="${1:-120}"
  local start=$SECONDS

  log_info "Waiting for infra services to become healthy (timeout: ${timeout}s)..."

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
# Start Directus CMS + push schema migrations
# ─────────────────────────────────────────────────────────────
start_directus() {
  log_step "Directus CMS"

  if [[ ! -d "$DIRECTUS_DIR" ]]; then
    log_warn "areadev-directus-cms-v1 not found at $DIRECTUS_DIR, skipping"
    return 0
  fi

  cd "$DIRECTUS_DIR"
  log_info "Starting Directus..."
  docker compose up -d
  log_ok "Directus container starting"

  # Wait for Directus to be healthy
  log_info "Waiting for Directus health..."
  local timeout=120 start=$SECONDS
  while ! curl -fsS http://localhost:8055/server/health >/dev/null 2>&1; do
    if (( SECONDS - start > timeout )); then
      log_err "Directus did not become healthy within ${timeout}s"
      docker compose logs directus 2>/dev/null | tail -10
      return 1
    fi
    sleep 3
  done
  log_ok "Directus is healthy"

  # Push schema migrations via directus-sync
  log_info "Pushing Directus schema migrations (directus-sync)..."
  if docker exec directus_cms npx directus-sync push -y 2>"$LOGS_DIR/directus-sync.log"; then
    log_ok "Directus schema migrations applied"
  else
    log_warn "directus-sync push had issues (see .logs/directus-sync.log)"
  fi
}

# ─────────────────────────────────────────────────────────────
# Start API dev server in background
# ─────────────────────────────────────────────────────────────
start_api() {
  log_step "API Server"

  if [[ ! -d "$API_DIR" ]]; then
    log_warn "areadev-api-2025 not found at $API_DIR, skipping"
    return 0
  fi

  cd "$API_DIR"
  log_info "Starting API dev server (pnpm dev)..."
  pnpm dev >"$LOGS_DIR/api.log" 2>&1 &
  echo $! >"$PIDS_DIR/api.pid"
  log_ok "API server started (pid=$(cat "$PIDS_DIR/api.pid"), logs: .logs/api.log)"

  # Wait briefly for API to respond
  local timeout=30 start=$SECONDS
  while ! curl -fsS http://localhost:8000/api/v1 >/dev/null 2>&1; do
    if (( SECONDS - start > timeout )); then
      log_warn "API not responding yet — check .logs/api.log"
      return 0
    fi
    sleep 2
  done
  log_ok "API responding at http://localhost:8000"
}

# ─────────────────────────────────────────────────────────────
# Start Frontend (Nuxt) dev server in background
# ─────────────────────────────────────────────────────────────
start_frontend() {
  log_step "Frontend (Nuxt)"

  if [[ ! -d "$FRONTEND_DIR" ]]; then
    log_warn "areadev-frontend-2025 not found at $FRONTEND_DIR, skipping"
    return 0
  fi

  cd "$FRONTEND_DIR"
  log_info "Starting frontend dev server (pnpm dev)..."
  pnpm dev >"$LOGS_DIR/frontend.log" 2>&1 &
  echo $! >"$PIDS_DIR/frontend.pid"
  log_ok "Frontend server started (pid=$(cat "$PIDS_DIR/frontend.pid"), logs: .logs/frontend.log)"

  # Wait briefly for frontend to respond
  local timeout=60 start=$SECONDS
  while ! curl -fsS http://localhost:3000 >/dev/null 2>&1; do
    if (( SECONDS - start > timeout )); then
      log_warn "Frontend not responding yet — check .logs/frontend.log"
      return 0
    fi
    sleep 3
  done
  log_ok "Frontend responding at http://localhost:3000"
}

# ─────────────────────────────────────────────────────────────
# Print status table
# ─────────────────────────────────────────────────────────────
print_status() {
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN} Full Stack Running${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
  printf "  %-15s %-8s %s\n" "SERVICE" "PORT" "URL"
  printf "  %-15s %-8s %s\n" "───────────────" "────────" "─────────────────────────────────────────"
  printf "  %-15s %-8s %s\n" "PostGIS 16" "5432" "postgresql://directus:directus@localhost:5432/directus"
  printf "  %-15s %-8s %s\n" "MSSQL 2019" "1433" "mssql://sa:YourStrongPassword123@localhost:1433"
  printf "  %-15s %-8s %s\n" "Redis 7" "6379" "redis://localhost:6379"
  printf "  %-15s %-8s %s\n" "LocalStack S3" "4566" "http://localhost:4566"
  printf "  %-15s %-8s %s\n" "ETL Cron" "—" "(scheduler — runs every 6h)"
  printf "  %-15s %-8s %s\n" "Directus CMS" "8055" "http://localhost:8055"
  printf "  %-15s %-8s %s\n" "API" "8000" "http://localhost:8000/api/v1"
  printf "  %-15s %-8s %s\n" "Frontend" "3000" "http://localhost:3000"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${BLUE}Directus Admin:${NC}  http://localhost:8055/admin"
  echo -e "  ${BLUE}S3 Health:${NC}       http://localhost:4566/_localstack/health"
  echo -e "  ${BLUE}API Docs:${NC}        http://localhost:8000/api/v1"
  echo -e "  ${BLUE}App:${NC}             http://localhost:3000"
  echo ""
  echo -e "  ${YELLOW}Logs:${NC} tail -f .logs/{api,frontend,directus-sync}.log"
  echo -e "  ${YELLOW}Stop:${NC} scripts/stop.sh"
  echo ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
main() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE} areadev-infra-2026 — Starting Full Stack${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  init_submodules
  start_infra
  wait_for_infra 120
  start_directus
  start_api
  start_frontend
  print_status
}

main "$@"
