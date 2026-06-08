#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# nuke.sh — Destroy all containers, volumes, and data
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

cd "$PROJECT_ROOT"

# ─────────────────────────────────────────────────────────────
# Confirmation prompt (unless --yes flag)
# ─────────────────────────────────────────────────────────────
if [[ "${1:-}" != "--yes" && "${1:-}" != "-y" ]]; then
  echo ""
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED} ⚠️  WARNING: This will destroy ALL data${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  This will remove:"
  echo "    • All Docker containers"
  echo "    • All named volumes (PostgreSQL, MSSQL, Redis, LocalStack data)"
  echo "    • All orphaned containers"
  echo ""
  read -rp "  Type 'nuke' to confirm: " confirmation
  echo ""

  if [[ "$confirmation" != "nuke" ]]; then
    log_warn "Aborted. No data was destroyed."
    exit 0
  fi
fi

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED} Nuking infrastructure...${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PROJECTS_DIR="$(dirname "$PROJECT_ROOT")"

# Tear down sibling project containers that share the areadev-net network
for dir in "$PROJECTS_DIR/areadev-directus-cms-v1" "$PROJECTS_DIR/areadev-api-2025" "$PROJECTS_DIR/areadev-frontend-2025"; do
  if [[ -f "$dir/docker-compose.yml" || -f "$dir/compose.yml" ]]; then
    log_info "Stopping containers in $(basename "$dir")..."
    (cd "$dir" && docker compose down --remove-orphans 2>/dev/null) || true
  fi
done

log_info "Stopping and removing infrastructure containers..."
docker compose down --volumes --remove-orphans 2>/dev/null || true

log_info "Removing named volumes..."
docker volume rm infra-postgis-data infra-mssql-data infra-redis-data infra-localstack-data 2>/dev/null || true

log_info "Removing any dangling images from this project..."
docker image prune -f --filter "label=com.docker.compose.project=areadev-infra-2026" 2>/dev/null || true

echo ""
log_ok "All infrastructure data destroyed. Run 'scripts/start.sh' to rebuild from scratch."
