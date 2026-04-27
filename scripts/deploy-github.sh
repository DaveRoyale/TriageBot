#!/bin/bash

# Deploy script to pull latest code from GitHub and restart the application
# Usage: ./scripts/deploy-github.sh <instance-id> [github-repo-url]
# Example: ./scripts/deploy-github.sh i-0900d85ce1eeac7ec https://github.com/DaveRoyale/TriageBot.git

set -e

if [ -z "$1" ]; then
    echo "Error: EC2 instance ID required"
    echo "Usage: $0 <instance-id> [github-repo-url]"
    echo ""
    echo "Example:"
    echo "  $0 i-0900d85ce1eeac7ec"
    echo "  $0 i-0900d85ce1eeac7ec https://github.com/DaveRoyale/TriageBot.git"
    exit 1
fi

INSTANCE_ID="$1"
GITHUB_REPO="${2:-https://github.com/DaveRoyale/TriageBot.git}"
REGION="${AWS_REGION:-ap-southeast-2}"
APP_DIR="/opt/triagebot"

echo "=========================================="
echo "TriageBot GitHub Deployment"
echo "=========================================="
echo "Instance ID: $INSTANCE_ID"
echo "GitHub repo: $GITHUB_REPO"
echo "Region: $REGION"
echo ""

# Deploy via SSM
echo "Executing deployment commands on instance..."
COMMAND_ID=$(aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "echo \"Pulling latest code from GitHub...\"",
    "cd /tmp && rm -rf triagebot-repo",
    "git clone '"$GITHUB_REPO"' triagebot-repo",
    "cd triagebot-repo",
    "echo \"Copying application files...\"",
    "cp -r app '"$APP_DIR"/"'",
    "cp requirements.txt '"$APP_DIR"/"'",
    "echo \"Installing/updating dependencies...\"",
    "'"$APP_DIR"'/venv/bin/pip install -r '"$APP_DIR"'/requirements.txt",
    "echo \"Restarting application service...\"",
    "systemctl restart triagebot",
    "sleep 2",
    "systemctl status triagebot --no-pager | head -10",
    "echo \"Testing application...\"",
    "curl -s http://localhost:8000/ | head -5"
  ]' \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Command.CommandId" \
  --output text)

echo "Command ID: $COMMAND_ID"
echo ""

# Wait for command to complete
echo "Waiting for deployment to complete (this may take 30-60 seconds)..."
for i in {1..60}; do
    STATUS=$(aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$REGION" \
      --query "Status" \
      --output text 2>/dev/null || echo "Pending")

    if [ "$STATUS" = "Success" ] || [ "$STATUS" = "Failed" ]; then
        break
    fi

    echo -ne "\rStatus: $STATUS (${i}s)"
    sleep 1
done

echo ""
echo ""

# Get output
echo "=========================================="
echo "Deployment Output"
echo "=========================================="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" \
  --output text

# Check for errors
if aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardErrorContent" \
  --output text | grep -q "ERROR\|failed\|Error"; then
    echo ""
    echo "=========================================="
    echo "Errors Detected"
    echo "=========================================="
    aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$REGION" \
      --query "StandardErrorContent" \
      --output text
    exit 1
fi

echo ""
echo "=========================================="
echo "Deployment completed successfully!"
echo "=========================================="
