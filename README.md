# areadev-infra-2026

Centralized infrastructure for the AreaDevelopment platform. Provides all local development services via Docker Compose and production infrastructure via AWS CDK.

## Why This Exists

Previously, each project managed its own databases and services independently:
- Directus had its own PostGIS + Redis in its docker-compose
- ETL had its own MSSQL + Postgres in a separate docker-compose
- S3 storage pointed at a real AWS bucket even in development
- There was no single command to start the full stack

This caused problems:
- **Port conflicts** when running multiple projects simultaneously
- **Inconsistent data** — each project had isolated databases that drifted out of sync
- **Slow onboarding** — new developers had to figure out 4+ docker-compose files and their startup order
- **No parity with production** — local dev used different PostgreSQL versions, different Redis versions, real S3 instead of emulated services

**areadev-infra-2026** solves this by providing one repo that owns all shared services and a single `scripts/start.sh` that brings up the entire AreaDevelopment platform in the correct order.

## Quick Start

```bash
# 1. Clone (into your Projects directory alongside the other repos)
git clone git@github.com:AreaDevelopment/areadev-infra-2026.git
cd areadev-infra-2026

# 2. Configure
cp .env.example .env
# Edit .env with your values (defaults work for most local dev)

# 3. Start the full stack
scripts/start.sh

# 4. Stop everything when done
scripts/stop.sh
```

## Scripts

### `scripts/start.sh` — Start the Full Stack

The primary script for local development. Brings up everything in the correct dependency order:

1. **Git submodules** — Updates submodules in all sibling projects (e.g., Directus extension forks)
2. **Install & build** — Runs `pnpm install` in Directus, API, and Frontend if dependencies are stale. Builds Directus extensions if their `dist/` is outdated.
3. **Infrastructure** — Starts Docker containers (PostGIS, MSSQL, Redis, LocalStack, ETL cron) and waits for all healthchecks to pass
4. **Directus CMS** — Starts the Directus container, waits for it to be healthy, then pushes schema migrations via `directus-sync`
5. **API** — Starts `pnpm dev` in the background (pid tracked for clean shutdown)
6. **Frontend** — Starts `pnpm dev` in the background (pid tracked for clean shutdown)

**Why it's needed:** Without this, you'd need to manually run 4+ docker-compose files in the right order, wait for databases to be healthy before starting apps, ensure extensions are built, and remember to push Directus migrations after every schema change.

---

### `scripts/stop.sh` — Stop the Full Stack

Gracefully shuts down everything in reverse order:

1. Frontend (kills background process via stored PID)
2. API (kills background process via stored PID)
3. Directus CMS (docker compose stop)
4. Infrastructure services (docker compose stop)

**Why it's needed:** A simple `Ctrl+C` only kills the foreground process. Background API/Frontend servers and Docker containers would keep running, holding ports and consuming resources. This script ensures clean shutdown with no orphaned processes.

---

### `scripts/health.sh` — Health Check All Services

Queries the Docker healthcheck status of each infrastructure container and reports a pass/fail table. Exits with code 0 if all healthy, code 1 if any service is unhealthy.

```
  ✓ PostGIS 16      5432       healthy
  ✓ MSSQL 2019      1433       healthy
  ✓ Redis 7         6379       healthy
  ✓ LocalStack      4566       healthy
  ✓ ETL Cron        —          running
```

**Why it's needed:** When something isn't working, you need to quickly identify which service is down without manually running `docker ps` and parsing output. Also used by the orchestrator's automated startup to gate app launches on infra health.

---

### `scripts/nuke.sh` — Destroy All Data

Removes all Docker containers, named volumes, and data. Requires typing `nuke` to confirm (or pass `--yes` to skip).

This destroys:
- All PostgreSQL data (Directus schema, content, ETL target tables)
- MSSQL data (legacy source database)
- Redis cache
- LocalStack state (S3 buckets and their contents)

**Why it's needed:** Sometimes you need a completely clean slate — corrupted database state, testing fresh migrations, or debugging init scripts. Without this, you'd need to remember all the volume names and manually remove them.

---

### `scripts/rebuild.sh` — Full Rebuild from Scratch

Runs `nuke --yes` then rebuilds all Docker images with `--no-cache` and starts fresh.

**Why it's needed:** When Dockerfiles change (e.g., new PostGIS version, updated MSSQL restore script), cached layers may serve stale images. This ensures you're running exactly what's defined in the current Dockerfiles.

---

### `scripts/submodules.sh` — Update Git Submodules

Scans all sibling `areadev-*` project directories for `.gitmodules` files and runs `git submodule update --init --recursive` in each.

Currently updates:
- `areadev-directus-cms-v1` — 3 extension submodules (flexible-editor, datawrapper-chart, vimeo-videos)

**Why it's needed:** Directus extensions are maintained as separate repos but mounted as git submodules. After cloning or switching branches, submodules need explicit initialization — developers often forget this step and get confusing "module not found" errors.

---

## Local Services

| Service | Port | Container | Description |
|---------|------|-----------|-------------|
| PostGIS 16 | 5432 | infra-postgis | Primary database (Aurora Serverless v2 PG16 compatible) |
| MSSQL 2019 | 1433 | infra-mssql | Legacy data source for ETL pipeline |
| Redis 7 | 6379 | infra-redis | Cache layer for Directus CMS |
| LocalStack 3.8 | 4566 | infra-localstack | AWS S3/SQS emulation (replaces real AWS in dev) |
| ETL Cron | — | infra-etl-cron | node-cron scheduler running incremental sync every 6h |
| Directus CMS | 8055 | directus_cms | Headless CMS (content management) |
| API | 8000 | — (host) | Express.js REST API |
| Frontend | 3000 | — (host) | Nuxt 4 SSR application |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  areadev-infra-2026                       │
│  ┌──────────┐ ┌──────────┐ ┌───────┐ ┌──────────────┐  │
│  │ PostGIS  │ │  MSSQL   │ │ Redis │ │  LocalStack  │  │
│  │   :5432  │ │  :1433   │ │ :6379 │ │    :4566     │  │
│  └────┬─────┘ └────┬─────┘ └───┬───┘ └──────┬───────┘  │
│       │             │           │             │          │
│       └─────────────┼───────────┼─────────────┘          │
│                     │    areadev-net                      │
└─────────────────────┼───────────┼────────────────────────┘
                      │           │
    ┌─────────────────┼───────────┼─────────────────┐
    │                 │           │                  │
┌───┴────┐  ┌────────┴──┐  ┌────┴─────┐  ┌────────┴──┐
│Directus│  │  ETL Sync │  │   API    │  │ Frontend  │
│  CMS   │  │  (cron)   │  │  :8000   │  │   :3000   │
│  :8055 │  │           │  │          │  │           │
└────────┘  └───────────┘  └──────────┘  └───────────┘
```

## AWS CDK (Production)

The `aws/` directory contains CDK stacks for production deployment:

```bash
cd aws
npm install
npx cdk synth                      # Validate templates
npx cdk deploy --all -c stage=stage  # Deploy staging
npx cdk deploy --all -c stage=prod   # Deploy production
```

### Stacks

| Stack | Resources |
|-------|-----------|
| VPC | VPC, subnets, NAT, security groups |
| Database | Aurora Serverless v2 (PostgreSQL 16) |
| Storage | S3 buckets (assets, deployments) |
| Cache | ElastiCache Redis 7.1 |
| ETL | Lambda + EventBridge schedule |
| API | Lambda + API Gateway + CloudFront |
| Frontend | Lambda + S3 + CloudFront |
| CMS | ECS Fargate (Directus) + ALB |

## Project Dependencies

This repo works alongside:
- [areadev-directus-cms-v1](https://github.com/AreaDevelopment/areadev-directus-cms-v1) — CMS (branch: `infra/centralized-services`)
- [areadev-etl-2024](https://github.com/AreaDevelopment/areadev-etl-2024) — ETL pipeline (branch: `infra/centralized-services`)
- [areadev-api-2025](https://github.com/AreaDevelopment/areadev-api-2025) — Backend API (branch: `infra/centralized-services`)
- [areadev-frontend-2025](https://github.com/AreaDevelopment/areadev-frontend-2025) — Nuxt frontend (branch: `infra/centralized-services`)
- [areadev-orchestrator](https://github.com/AreaDevelopment/areadev-orchestrator) — Dev orchestration (branch: `infra/centralized-services`)

## MSSQL Database Restore

To restore the legacy AreaDevelopment MSSQL backup:

```bash
# Place your .bak file in services/mssql/ directory
docker cp ./areadevelopment.bak infra-mssql:/var/opt/mssql/backup/

# Execute the restore script
docker exec infra-mssql /var/opt/mssql/restore_db.sh
```
