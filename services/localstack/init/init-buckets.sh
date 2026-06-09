#!/bin/bash
# LocalStack init script — runs when LocalStack is ready
# Creates S3 buckets needed for local development
set -e

echo "Initializing LocalStack resources..."

# Create Directus storage bucket
awslocal s3 mb s3://areadev-directus-storage-dev-1 2>/dev/null || true
awslocal s3api put-bucket-acl --bucket areadev-directus-storage-dev-1 --acl public-read

# Enable CORS so the frontend can load images directly from S3
awslocal s3api put-bucket-cors --bucket areadev-directus-storage-dev-1 --cors-configuration '{
  "CORSRules": [{
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3600
  }]
}'

echo "Created S3 bucket: areadev-directus-storage-dev-1 (with CORS)"

# List buckets for verification
awslocal s3 ls

echo "LocalStack initialization complete."
