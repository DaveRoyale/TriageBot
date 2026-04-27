# TriageBot Deployment Scripts

Operational scripts for deploying and managing TriageBot EC2 instances.

## Quick Reference

```bash
# Deploy latest code from GitHub
./scripts/deploy-github.sh <instance-id>

# Check instance health and diagnostics
./scripts/verify-instance.sh <instance-id>

# Recover broken instance via SSM
aws ssm send-command --document-name AWS-RunShellScript --instance-ids <id> \
  --parameters 'commands=["curl -s https://raw.githubusercontent.com/DaveRoyale/TriageBot/master/scripts/recover-instance.sh | bash"]'
```

## Scripts Overview

### deploy-github.sh
Pull latest code from GitHub and deploy to running instance.

```bash
./scripts/deploy-github.sh i-0900d85ce1eeac7ec
./scripts/deploy-github.sh i-0900d85ce1eeac7ec https://github.com/YourOrg/TriageBot.git
```

**What it does:**
- Clones latest code from GitHub
- Updates app/ and requirements.txt on instance
- Installs/upgrades Python dependencies
- Restarts triagebot service
- Verifies application is running

### verify-instance.sh
Comprehensive health check and diagnostics for deployed instance.

```bash
./scripts/verify-instance.sh i-0900d85ce1eeac7ec ap-southeast-2
```

**Checks:**
- Instance running and has public IP
- Application code structure
- Python venv setup and executables
- Service status and recent logs
- Port 8000 listening
- Application HTTP response
- Installed dependencies
- Internet accessibility

### recover-instance.sh
Manually recover instance if bootstrap failed or services are broken.

**Run via SSM:**
```bash
aws ssm send-command --document-name AWS-RunShellScript --instance-ids i-0900d85ce1eeac7ec \
  --parameters 'commands=["curl -s https://raw.githubusercontent.com/DaveRoyale/TriageBot/master/scripts/recover-instance.sh | bash"]'
```

**Fixes:**
- Missing or broken Python venv
- Failed dependency installation
- Missing systemd service file
- Service startup failures

## Key Lessons Learned

### Virtual Environment Setup
- Use explicit Python version: `python3.11 -m venv`
- Use full paths to pip: `/opt/triagebot/venv/bin/pip install`
- Verify executables exist after creation
- Never rely on `source activate` in scripts

### GitHub Deployment
- Configure .gitignore BEFORE committing large files
- Keep GitHub as source of truth
- Avoid committing venv/, .terraform/, binaries

### Service Management
- Use absolute paths in ExecStart
- Set PYTHONUNBUFFABLE=1 for logging
- Always verify service starts
- Check journalctl logs for debugging

### Remote Access
- Use AWS SSM (Systems Manager) for commands
- No SSH key management needed
- Better security and audit trail
- Works without public IP if instance has IAM role
