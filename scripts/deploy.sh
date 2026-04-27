#!/bin/bash

# Deploy script to package and upload TriageBot code to S3
# Usage: ./scripts/deploy.sh <s3-bucket-name>

set -e

if [ -z "$1" ]; then
    echo "Error: S3 bucket name required"
    echo "Usage: $0 <s3-bucket-name>"
    echo ""
    echo "You can find the bucket name in terraform outputs:"
    echo "  terraform -chdir=terraform output s3_bucket_name"
    exit 1
fi

S3_BUCKET="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT="$REPO_ROOT"

echo "=========================================="
echo "TriageBot Deployment Script"
echo "=========================================="
echo "Application root: $APP_ROOT"
echo "S3 bucket: $S3_BUCKET"
echo ""

# Create temporary directory for packaging
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Packaging application..."

# Copy application files (exclude venv, __pycache__, etc)
mkdir -p "$TEMP_DIR/triagebot"

# Copy main app structure
cp -r "$APP_ROOT"/app "$TEMP_DIR/triagebot/" || echo "Note: app directory not found"
cp -r "$APP_ROOT"/guidance "$TEMP_DIR/triagebot/" || echo "Note: guidance directory not found"
cp -r "$APP_ROOT"/static "$TEMP_DIR/triagebot/" || echo "Note: static directory not found"
cp -r "$APP_ROOT"/templates "$TEMP_DIR/triagebot/" || echo "Note: templates directory not found"

# Copy config and requirements files
cp "$APP_ROOT"/requirements.txt "$TEMP_DIR/triagebot/" 2>/dev/null || {
    echo "Warning: requirements.txt not found. Make sure it exists in the repo root."
}
cp "$APP_ROOT"/config.yaml "$TEMP_DIR/triagebot/" 2>/dev/null || {
    echo "Note: config.yaml not found (optional)"
}

# Create the zip file
cd "$TEMP_DIR"
zip -r -q triagebot-code.zip triagebot/

echo "Created package: $TEMP_DIR/triagebot-code.zip"
echo "Package size: $(du -h $TEMP_DIR/triagebot-code.zip | cut -f1)"
echo ""

# Upload to S3
echo "Uploading to S3..."
aws s3 cp "$TEMP_DIR/triagebot-code.zip" "s3://$S3_BUCKET/triagebot-code.zip"

echo ""
echo "=========================================="
echo "Deployment successful!"
echo "=========================================="
echo ""
echo "The EC2 instance will download and extract this package on next boot/restart."
echo "If the instance is already running, SSH to it and restart the service:"
echo "  sudo systemctl restart triagebot"
echo ""
