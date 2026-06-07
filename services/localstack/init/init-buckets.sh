#!/bin/bash
# LocalStack init script — runs when LocalStack is ready
# Creates S3 buckets needed for local development
set -e

echo "Initializing LocalStack resources..."

# Create Directus storage bucket
awslocal s3 mb s3://areadev-directus-storage-dev-1 2>/dev/null || true
awslocal s3api put-bucket-acl --bucket areadev-directus-storage-dev-1 --acl public-read

echo "Created S3 bucket: areadev-directus-storage-dev-1"

# List buckets for verification
awslocal s3 ls

echo "LocalStack initialization complete."
