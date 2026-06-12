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
ETL_DIR="$PROJECTS_DIR/areadev-etl-2024"

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
# Install dependencies and build in each project
# ─────────────────────────────────────────────────────────────
install_and_build() {
  log_step "Installing Dependencies & Building"

  local projects=("$DIRECTUS_DIR" "$API_DIR" "$FRONTEND_DIR")
  local names=("Directus CMS" "API" "Frontend")

  for i in "${!projects[@]}"; do
    local dir="${projects[$i]}"
    local name="${names[$i]}"

    if [[ ! -d "$dir" ]]; then
      log_warn "$name not found at $dir, skipping"
      continue
    fi

    cd "$dir"

    # pnpm install (if node_modules is missing or lockfile changed)
    if [[ ! -d "node_modules" ]] || [[ "pnpm-lock.yaml" -nt "node_modules/.pnpm/lock.yaml" ]]; then
      log_info "$name — installing dependencies..."
      pnpm install --frozen-lockfile 2>"$LOGS_DIR/${name,,}-install.log" || \
        pnpm install 2>"$LOGS_DIR/${name,,}-install.log"
      log_ok "$name — dependencies installed"
    else
      log_ok "$name — dependencies up to date"
    fi
  done

  # Build Directus extensions (submodules)
  if [[ -d "$DIRECTUS_DIR" ]]; then
    cd "$DIRECTUS_DIR"
    for ext_dir in extensions/*/; do
      if [[ -f "$ext_dir/package.json" ]]; then
        local ext_name
        ext_name=$(basename "$ext_dir")
        if [[ ! -d "$ext_dir/dist" ]] || [[ "$ext_dir/src" -nt "$ext_dir/dist" ]]; then
          log_info "Building Directus extension: $ext_name..."
          (cd "$ext_dir" && pnpm install --frozen-lockfile 2>/dev/null || pnpm install && pnpm run build) \
            >"$LOGS_DIR/ext-$ext_name.log" 2>&1 && \
            log_ok "Extension $ext_name built" || \
            log_warn "Extension $ext_name build had issues (see .logs/ext-$ext_name.log)"
        else
          log_ok "Extension $ext_name — already built"
        fi
      fi
    done
  fi
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
# Restore S3 backup into LocalStack (if backup exists)
# LocalStack Community stores S3 in-memory; this re-imports
# objects that were exported by stop.sh before shutdown.
# ─────────────────────────────────────────────────────────────
restore_s3_backup() {
  local backup_dir="$PROJECT_ROOT/.s3-backup"
  local bucket="areadev-directus-storage-dev-1"

  if [[ ! -d "$backup_dir/$bucket" ]] || [[ -z "$(ls -A "$backup_dir/$bucket" 2>/dev/null)" ]]; then
    log_info "No S3 backup found — skipping restore"
    return 0
  fi

  log_step "Restoring S3 Backup"

  local file_count
  file_count=$(find "$backup_dir/$bucket" -type f | wc -l)
  log_info "Restoring $file_count files to s3://$bucket ..."

  # Copy backup into the container, then use awslocal to upload
  docker exec infra-localstack rm -rf /tmp/s3-restore 2>/dev/null || true
  docker exec infra-localstack mkdir -p /tmp/s3-restore
  docker cp "$backup_dir/$bucket" "infra-localstack:/tmp/s3-restore/$bucket"
  docker exec infra-localstack awslocal s3 sync \
    "/tmp/s3-restore/$bucket" "s3://$bucket" \
    --quiet
  docker exec infra-localstack rm -rf /tmp/s3-restore

  log_ok "S3 backup restored ($file_count files)"
}

# ─────────────────────────────────────────────────────────────
# Restore MSSQL legacy database (if not already present)
# ─────────────────────────────────────────────────────────────
restore_mssql() {
  log_step "MSSQL Legacy Database"

  local backup_file="$ETL_DIR/mssql/areadevelopment.bak"
  local sa_password="${MSSQL_SA_PASSWORD:-YourStrongPassword123}"

  # Check if AreaDevelopment database already exists
  local db_exists
  db_exists=$(docker exec infra-mssql /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$sa_password" -C -h -1 \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = 'AreaDevelopment'" -b 2>/dev/null | tr -d '[:space:]')

  if [[ "$db_exists" == "1" ]]; then
    log_ok "AreaDevelopment database already exists, skipping restore"
    return 0
  fi

  if [[ ! -f "$backup_file" ]]; then
    log_warn "Backup file not found at $backup_file — skipping MSSQL restore"
    log_warn "Place areadevelopment.bak in areadev-etl-2024/mssql/ to enable restore"
    return 0
  fi

  log_info "Restoring AreaDevelopment database from backup..."
  docker cp "$backup_file" infra-mssql:/var/opt/mssql/backup/areadevelopment.bak
  docker cp "$PROJECT_ROOT/services/mssql/restore_db.sh" infra-mssql:/var/opt/mssql/restore_db.sh
  docker exec infra-mssql chmod +x /var/opt/mssql/restore_db.sh
  if docker exec infra-mssql /var/opt/mssql/restore_db.sh 2>&1 | tee "$LOGS_DIR/mssql-restore.log"; then
    log_ok "AreaDevelopment database restored"
  else
    log_err "MSSQL restore failed (see .logs/mssql-restore.log)"
    return 1
  fi
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
  docker compose down --remove-orphans 2>/dev/null || true
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
  if docker exec directus_cms npx directus-sync push 2>"$LOGS_DIR/directus-sync.log"; then
    log_ok "Directus schema migrations applied"
  else
    log_warn "directus-sync push had issues (see .logs/directus-sync.log)"
  fi

  # Configure static API token for the admin user
  configure_directus_token

  # Ensure required folders exist (some field configs reference specific UUIDs)
  ensure_directus_folders
}

# ─────────────────────────────────────────────────────────────
# Set the admin user's static token so the ETL can authenticate
# ─────────────────────────────────────────────────────────────
configure_directus_token() {
  local etl_env="$ETL_DIR/.env"
  if [[ ! -f "$etl_env" ]]; then
    log_warn "ETL .env not found at $etl_env — skipping token configuration"
    return 0
  fi

  local api_token
  api_token=$(grep -E '^API_TOKEN=' "$etl_env" | cut -d= -f2-)
  if [[ -z "$api_token" ]]; then
    log_warn "API_TOKEN not set in ETL .env — skipping token configuration"
    return 0
  fi

  local admin_email="${DIRECTUS_ADMIN_EMAIL:-admin@example.com}"
  local admin_password="${DIRECTUS_ADMIN_PASSWORD:-d1r3ctu5}"

  # Check if the token already works
  local status user_response user_id
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $api_token" http://localhost:8055/users/me)
  if [[ "$status" == "200" ]]; then
    log_ok "Directus API token already valid"
    # Still sync the user ID in case it changed
    user_id=$(curl -s -H "Authorization: Bearer $api_token" http://localhost:8055/users/me \
      | node -e 'const d=require("fs").readFileSync(0,"utf8");try{const v=JSON.parse(d).data.id;if(!v)throw new Error("data.id missing");console.log(v)}catch(e){console.error("JSON parse error:",e.message);process.exit(1)}') \
      || log_warn "Could not extract user ID from Directus response"
    sync_directus_user_id "$etl_env" "$user_id"
    return 0
  fi

  log_info "Configuring Directus static API token..."

  # Login as admin to get a temporary access token
  local login_response
  login_response=$(curl -s -X POST http://localhost:8055/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$admin_email\",\"password\":\"$admin_password\"}")

  local access_token
  access_token=$(echo "$login_response" | node -e 'const d=require("fs").readFileSync(0,"utf8");try{const v=JSON.parse(d).data.access_token;if(!v)throw new Error("data.access_token missing");console.log(v)}catch(e){console.error("JSON parse error:",e.message);process.exit(1)}') \
    || { log_warn "Failed to parse Directus login response"; access_token=""; }
  if [[ -z "$access_token" ]]; then
    log_warn "Could not login to Directus — skipping token configuration"
    return 0
  fi

  # Get the admin user's ID
  local user_id
  user_id=$(curl -s -H "Authorization: Bearer $access_token" http://localhost:8055/users/me \
    | node -e 'const d=require("fs").readFileSync(0,"utf8");try{const v=JSON.parse(d).data.id;if(!v)throw new Error("data.id missing");console.log(v)}catch(e){console.error("JSON parse error:",e.message);process.exit(1)}') \
    || log_warn "Could not extract user ID from Directus response"

  # Set the static token on the admin user
  curl -s -X PATCH "http://localhost:8055/users/$user_id" \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -d "{\"token\":\"$api_token\"}" >/dev/null

  # Verify it works
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $api_token" http://localhost:8055/users/me)
  if [[ "$status" != "200" ]]; then
    log_warn "Failed to set Directus static token"
    return 0
  fi

  log_ok "Directus static API token configured"

  sync_directus_user_id "$etl_env" "$user_id"
}

# ─────────────────────────────────────────────────────────────
# Sync DEFAULT_DIRECTUS_USER in ETL .env to match admin UUID
# ─────────────────────────────────────────────────────────────
sync_directus_user_id() {
  local etl_env="$1"
  local user_id="$2"

  if [[ -z "$user_id" || -z "$etl_env" ]]; then
    return 0
  fi

  local current_user
  current_user=$(grep -E '^DEFAULT_DIRECTUS_USER=' "$etl_env" | cut -d= -f2-) || true
  if [[ "$current_user" != "$user_id" ]]; then
    if grep -qE '^DEFAULT_DIRECTUS_USER=' "$etl_env"; then
      sed -i "s/^DEFAULT_DIRECTUS_USER=.*/DEFAULT_DIRECTUS_USER=$user_id/" "$etl_env"
    else
      # Ensure trailing newline before appending
      [[ -s "$etl_env" && $(tail -c1 "$etl_env" | wc -l) -eq 0 ]] && echo "" >> "$etl_env"
      echo "DEFAULT_DIRECTUS_USER=$user_id" >> "$etl_env"
    fi
    log_ok "Updated DEFAULT_DIRECTUS_USER in ETL .env → $user_id"
  fi
}

# ─────────────────────────────────────────────────────────────
# Ensure required Directus folders exist
# Some field configs (e.g. Vimeo extension outputFolder) reference
# folder UUIDs that must be present in directus_folders.
# ─────────────────────────────────────────────────────────────
ensure_directus_folders() {
  log_info "Ensuring required Directus folders exist..."

  local etl_env="$ETL_DIR/.env"
  local api_token
  if [[ -f "$etl_env" ]]; then
    api_token=$(grep -E '^API_TOKEN=' "$etl_env" | cut -d= -f2-)
  fi
  if [[ -z "$api_token" ]]; then
    log_warn "No API token available — skipping folder check"
    return 0
  fi

  # Required folders: UUID → name
  declare -A required_folders=(
    ["f652c5b8-7532-444a-aa23-b1fd895f4b23"]="video thumbnails"
    ["02100a33-4212-4492-93e3-cb957d76cf06"]="podcast artwork"
  )

  local created=0
  for uuid in "${!required_folders[@]}"; do
    local name="${required_folders[$uuid]}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $api_token" \
      "http://localhost:8055/folders/$uuid")

    if [[ "$status" == "200" ]]; then
      continue
    fi

    # Create the folder with the specific UUID
    local resp
    resp=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8055/folders" \
      -H "Authorization: Bearer $api_token" \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"$uuid\",\"name\":\"$name\"}")

    local code
    code=$(echo "$resp" | tail -1)
    if [[ "$code" == "200" || "$code" == "204" ]]; then
      log_ok "Created Directus folder: $name ($uuid)"
      (( created++ ))
    else
      log_warn "Failed to create folder '$name' ($uuid) — HTTP $code"
    fi
  done

  if (( created == 0 )); then
    log_ok "All required Directus folders present"
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
  install_and_build
  start_infra
  wait_for_infra 120
  restore_s3_backup
  restore_mssql
  start_directus
  start_api
  start_frontend
  print_status
}

main "$@"
