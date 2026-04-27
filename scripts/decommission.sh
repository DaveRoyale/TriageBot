#!/bin/bash

# Decommission script to tear down TriageBot infrastructure
# This safely destroys all AWS resources created by Terraform

set -e

echo "=========================================="
echo "TriageBot Decommissioning Script"
echo "=========================================="
echo ""
echo "WARNING: This will destroy all AWS resources created by Terraform:"
echo "  - EC2 instance"
echo "  - EBS volume"
echo "  - VPC and subnet"
echo "  - Security groups"
echo "  - S3 bucket (WARNING: with all contents)"
echo "  - IAM roles and policies"
echo ""
read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled. No resources were deleted."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

echo ""
echo "Running terraform destroy..."
terraform -chdir="$TERRAFORM_DIR" destroy -auto-approve

echo ""
echo "=========================================="
echo "Decommissioning complete!"
echo "=========================================="
echo ""
echo "All AWS resources have been deleted."
echo ""
