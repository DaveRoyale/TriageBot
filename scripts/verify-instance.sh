#!/bin/bash

# Verification script to check the health and status of a deployed TriageBot instance
# Usage: ./scripts/verify-instance.sh <instance-id> [region]

set -e

if [ -z "$1" ]; then
    echo "Error: EC2 instance ID required"
    echo "Usage: $0 <instance-id> [region]"
    echo ""
    echo "Example:"
    echo "  $0 i-0900d85ce1eeac7ec"
    echo "  $0 i-0900d85ce1eeac7ec ap-southeast-2"
    exit 1
fi

INSTANCE_ID="$1"
REGION="${2:-ap-southeast-2}"

echo "=========================================="
echo "TriageBot Instance Verification"
echo "=========================================="
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo ""

# Check instance state
echo "Checking instance state..."
INSTANCE_STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text)

if [ "$INSTANCE_STATE" != "running" ]; then
    echo "ERROR: Instance is not running. Current state: $INSTANCE_STATE"
    exit 1
fi
echo "✓ Instance is running"

# Get instance IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

if [ "$PUBLIC_IP" = "None" ] || [ -z "$PUBLIC_IP" ]; then
    echo "WARNING: Instance has no public IP address"
else
    echo "✓ Public IP: $PUBLIC_IP"
fi

echo ""
echo "Running diagnostics on instance..."

# Run diagnostic commands
COMMAND_ID=$(aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo \"=== System Information ===\"",
    "hostname",
    "uname -a",
    "echo \"\"",
    "echo \"=== Disk Space ===\"",
    "df -h /opt/triagebot",
    "echo \"\"",
    "echo \"=== Application Directory ===\"",
    "ls -la /opt/triagebot/",
    "echo \"\"",
    "echo \"=== Python Virtual Environment ===\"",
    "ls -la /opt/triagebot/venv/bin/python* /opt/triagebot/venv/bin/pip* 2>&1 | head -10",
    "/opt/triagebot/venv/bin/python --version 2>&1",
    "/opt/triagebot/venv/bin/pip --version 2>&1",
    "echo \"\"",
    "echo \"=== TriageBot Service Status ===\"",
    "systemctl status triagebot --no-pager | head -15",
    "echo \"\"",
    "echo \"=== TriageBot Service Logs (last 20 lines) ===\"",
    "journalctl -u triagebot -n 20 --no-pager",
    "echo \"\"",
    "echo \"=== Network Connectivity ===\"",
    "netstat -tlnp 2>/dev/null | grep -E \"8000|LISTEN\" || ss -tlnp 2>/dev/null | grep -E \"8000|LISTEN\"",
    "echo \"\"",
    "echo \"=== Application Health Check ===\"",
    "curl -s http://localhost:8000/ | head -5 && echo \"\" || echo \"Health check failed\"",
    "echo \"\"",
    "echo \"=== Dependencies Check ===\"",
    "/opt/triagebot/venv/bin/pip list | grep -E \"fastapi|uvicorn|anthropic\""
  ]' \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Command.CommandId" \
  --output text)

echo "Command ID: $COMMAND_ID"
echo "Waiting for diagnostics to complete..."

# Wait for completion
for i in {1..30}; do
    STATUS=$(aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$REGION" \
      --query "Status" \
      --output text 2>/dev/null || echo "Pending")

    if [ "$STATUS" = "Success" ] || [ "$STATUS" = "Failed" ]; then
        break
    fi
    sleep 1
done

echo ""
echo "=========================================="
echo "Diagnostics Output"
echo "=========================================="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" \
  --output text

# Show any errors
ERRORS=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardErrorContent" \
  --output text)

if [ -n "$ERRORS" ] && [ "$ERRORS" != "None" ]; then
    echo ""
    echo "=========================================="
    echo "Errors/Warnings"
    echo "=========================================="
    echo "$ERRORS"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="

# Try to reach the app
if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ]; then
    echo "Attempting to reach application at http://$PUBLIC_IP:8000..."
    if curl -s --max-time 5 "http://$PUBLIC_IP:8000/" > /dev/null 2>&1; then
        echo "✓ Application is accessible from the internet"
    else
        echo "✗ Application is NOT accessible from the internet"
        echo "  Check security group rules and network configuration"
    fi
fi

echo ""
echo "For more detailed logs, SSH to the instance and run:"
echo "  journalctl -u triagebot -f"
