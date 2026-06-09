#!/bin/bash
# LocalStack init script — runs when LocalStack is ready
# Creates S3 buckets needed for local development
# Skips creation if the bucket already exists (preserves persisted data)
set -e

BUCKET="areadev-directus-storage-dev-1"

echo "Initializing LocalStack resources..."

if awslocal s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket $BUCKET already exists — skipping creation (data preserved)"
else
  awslocal s3 mb "s3://$BUCKET"
  awslocal s3api put-bucket-acl --bucket "$BUCKET" --acl public-read
  echo "Created S3 bucket: $BUCKET"
fi

# Ensure CORS is set (idempotent)
awslocal s3api put-bucket-cors --bucket "$BUCKET" --cors-configuration '{
  "CORSRules": [{
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3600
  }]
}'

# List buckets for verification
awslocal s3 ls

echo "LocalStack initialization complete."
