# areadev-infra-2026

Centralized infrastructure for the AreaDevelopment platform. Provides all local development services via Docker Compose and production infrastructure via AWS CDK.

## Quick Start

```bash
# 1. Clone
git clone git@github.com:AreaDevelopment/areadev-infra-2026.git
cd areadev-infra-2026

# 2. Configure
cp .env.example .env
# Edit .env with your values

# 3. Start everything
scripts/start.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/start.sh` | Start all services, init submodules, wait for health |
| `scripts/stop.sh` | Gracefully stop all services (preserves data) |
| `scripts/health.sh` | Check health of all services |
| `scripts/nuke.sh` | Destroy ALL data and volumes (requires confirmation) |
| `scripts/rebuild.sh` | Nuke + rebuild images from scratch |
| `scripts/submodules.sh` | Init/update git submodules in all sibling projects |

## Local Services

| Service | Port | Container | Description |
|---------|------|-----------|-------------|
| PostGIS 16 | 5432 | infra-postgis | Primary database (Aurora Serverless v2 compatible) |
| MSSQL 2019 | 1433 | infra-mssql | Legacy data source for ETL |
| Redis 7 | 6379 | infra-redis | Cache layer for Directus CMS |
| LocalStack | 4566 | infra-localstack | AWS service emulation (S3, SQS) |
| ETL Cron | — | infra-etl-cron | Scheduled sync jobs |

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
│  CMS   │  │  (cron)   │  │  :3001   │  │   :3000   │
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
