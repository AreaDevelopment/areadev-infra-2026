#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# health.sh — Check health of all infrastructure services
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

cd "$PROJECT_ROOT"

all_healthy=true

check_service() {
  local name="$1"
  local container="$2"
  local port="$3"

  local status
  status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_running")

  local icon
  case "$status" in
    healthy)     icon="${GREEN}✓${NC}" ;;
    unhealthy)   icon="${RED}✗${NC}"; all_healthy=false ;;
    starting)    icon="${YELLOW}⋯${NC}"; all_healthy=false ;;
    *)           icon="${RED}✗${NC}"; status="not running"; all_healthy=false ;;
  esac

  printf "  %b %-15s %-10s %s\n" "$icon" "$name" "$port" "$status"
}

check_container_running() {
  local name="$1"
  local container="$2"

  local running
  running=$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null || echo "false")

  local icon
  if [[ "$running" == "true" ]]; then
    icon="${GREEN}✓${NC}"
    printf "  %b %-15s %-10s %s\n" "$icon" "$name" "—" "running"
  else
    icon="${RED}✗${NC}"
    all_healthy=false
    printf "  %b %-15s %-10s %s\n" "$icon" "$name" "—" "not running"
  fi
}

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE} Infrastructure Health Check${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
printf "  %-3s %-15s %-10s %s\n" "" "SERVICE" "PORT" "STATUS"
printf "  %-3s %-15s %-10s %s\n" "" "───────────────" "──────────" "──────────"

check_service "PostGIS 16" "infra-postgis" "5432"
check_service "MSSQL 2019" "infra-mssql" "1433"
check_service "Redis 7" "infra-redis" "6379"
check_service "LocalStack" "infra-localstack" "4566"
check_container_running "ETL Cron" "infra-etl-cron"

echo ""

if $all_healthy; then
  echo -e "  ${GREEN}All services healthy ✓${NC}"
  echo ""
  exit 0
else
  echo -e "  ${RED}Some services are unhealthy ✗${NC}"
  echo ""
  exit 1
fi
