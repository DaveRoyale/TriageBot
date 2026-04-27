# TriageBot Deployment Guide

Complete guide to deploying and managing TriageBot on AWS EC2.

## Quick Start

### First Time Setup (5-15 minutes)

```bash
# 1. Initialize Terraform
cd terraform
terraform init

# 2. Deploy to testing environment
terraform apply -var-file=testing.tfvars

# 3. Wait 5-10 minutes for bootstrap to complete
# 4. Verify deployment
INSTANCE_ID=$(terraform output -raw ec2_instance_id)
../scripts/verify-instance.sh $INSTANCE_ID

# 5. Access application
PUBLIC_IP=$(terraform output -raw ec2_public_ip)
open http://$PUBLIC_IP:8000
```

## Prerequisites

- AWS CLI v2 with credentials configured
- Terraform >= 1.0
- Bash shell
- Git
- Code pushed to GitHub repository

## Deployment Process

### 1. Prepare Code

Ensure code is in GitHub (source of truth):

```bash
# Verify .gitignore is configured
cat .gitignore | grep -E "venv|.terraform|*.tfstate"

# Push to GitHub
git add -A
git commit -m "Ready for deployment"
git push origin master
```

### 2. Initialize Terraform

```bash
cd terraform
terraform init

# This downloads AWS provider (one-time setup)
```

### 3. Plan Deployment

```bash
# For testing (small instance, cheap)
terraform plan -var-file=testing.tfvars

# For production (larger instance)
terraform plan -var-file=production.tfvars
```

Review the output:
- 1 VPC with public subnet
- 1 security group (allows port 8000)
- 1 EC2 instance
- 1 Elastic IP for consistent public address

### 4. Apply Configuration

```bash
terraform apply -var-file=testing.tfvars
```

**Outputs saved:**
- `ec2_instance_id` - Instance ID
- `ec2_public_ip` - Public IP address
- `app_url` - Application URL

### 5. Wait for Bootstrap

Instance automatically runs `bootstrap.sh` during startup (~5-10 minutes):

```bash
# Monitor bootstrap via System Manager
INSTANCE_ID=$(terraform output -raw ec2_instance_id)

# Bootstrap log location: /var/log/triagebot-bootstrap.log
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids $INSTANCE_ID --region ap-southeast-2 \
  --parameters 'commands=["tail -f /var/log/triagebot-bootstrap.log"]'
```

### 6. Verify Deployment

```bash
./scripts/verify-instance.sh $INSTANCE_ID
```

Should show:
- ✓ Instance is running
- ✓ Application code is present
- ✓ Python venv configured
- ✓ Service is running
- ✓ Application responds to HTTP requests

### 7. Access Application

```bash
PUBLIC_IP=$(terraform output -raw ec2_public_ip)
curl http://$PUBLIC_IP:8000
# Or open in browser: http://$PUBLIC_IP:8000
```

## Updating Application

### Push Code Update

```bash
# Make changes
git add .
git commit -m "Update feature X"
git push origin master
```

### Deploy to Instance

```bash
INSTANCE_ID=$(terraform output -raw ec2_instance_id)
./scripts/deploy-github.sh $INSTANCE_ID
```

This:
- Clones latest code from GitHub
- Updates app/ and requirements.txt
- Installs new dependencies
- Restarts the service
- Verifies it's working

## Troubleshooting

### Application Not Responding

```bash
# Get detailed diagnostics
./scripts/verify-instance.sh <instance-id>

# Check service status
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids <id> --parameters 'commands=["systemctl status triagebot"]'

# Check service logs (last 50 lines)
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids <id> --parameters 'commands=["journalctl -u triagebot -n 50"]'
```

### Bootstrap Failed

If instance doesn't respond after 15 minutes:

```bash
# Run recovery script
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids <instance-id> \
  --parameters 'commands=["curl -s https://raw.githubusercontent.com/DaveRoyale/TriageBot/master/scripts/recover-instance.sh | bash"]'
```

### Network/Access Issues

```bash
# Verify security group allows port 8000
terraform output security_group_id
aws ec2 describe-security-groups --group-ids <sg-id> \
  --query "SecurityGroups[0].IpPermissions"

# Verify instance has public IP
terraform output ec2_public_ip

# Test connectivity from local machine
curl -v http://<public-ip>:8000/
```

## Cost Optimization

### Testing Configuration (t3.medium)
- $0.04/hour running
- 20GB storage
- Use for development/testing

### Production Configuration (t3.large)
- $0.08/hour running
- 50GB storage
- Use for longer-running deployments

### Save Money
- Destroy instance when not in use: `terraform destroy`
- Use testing config during development
- Spot instances available via tfvars

## Scaling & Advanced

### Multiple Instances

Create additional tfvars files for different environments:

```bash
# Create staging configuration
cp testing.tfvars staging.tfvars
# Edit staging.tfvars to customize (instance type, etc.)

terraform apply -var-file=staging.tfvars
```

### Auto-scaling

Currently manual scaling. To set up auto-scaling:

1. Create launch template from current configuration
2. Create Auto Scaling Group
3. Set up load balancer (Application Load Balancer)

See terraform/CONFIGURATIONS.md for architecture options.

## Monitoring & Logging

### View Service Logs

```bash
INSTANCE_ID=$(terraform output -raw ec2_instance_id)

# Real-time logs
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids $INSTANCE_ID \
  --parameters 'commands=["journalctl -u triagebot -f"]'

# Last 100 lines
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids $INSTANCE_ID \
  --parameters 'commands=["journalctl -u triagebot -n 100 --no-pager"]'
```

### Bootstrap Log

```bash
# Check bootstrap progress/errors
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids $INSTANCE_ID \
  --parameters 'commands=["cat /var/log/triagebot-bootstrap.log"]'
```

### System Logs

```bash
# Check system errors
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids $INSTANCE_ID \
  --parameters 'commands=["dmesg | tail -50"]'
```

## Decommissioning

Destroy all AWS resources:

```bash
cd terraform
terraform destroy -var-file=testing.tfvars
# Confirm when prompted
```

This removes:
- EC2 instance
- VPC, subnets, security groups
- Elastic IP
- All AWS resources created

## Key Lessons

### Python Virtual Environment
- Always use explicit version: `python3.11 -m venv`
- Always use full paths to pip/python (don't source activate in scripts)
- Verify executables exist after venv creation

### Git Repository
- Configure .gitignore BEFORE committing large files
- Use GitHub as source of truth (not S3 artifacts)
- Keep clean repository without venv/, .terraform/, binaries

### Systemd Services
- Use absolute paths in ExecStart
- Set PYTHONUNBUFFERED=1 for real-time logging
- Always verify service status after restart
- Check journalctl for errors

### AWS Infrastructure
- Use Elastic IP for consistent public address
- Use AWS Systems Manager (SSM) for remote commands
- IAM roles give instances permissions (no SSH keys needed)
- Security groups control network access

## Additional Resources

- **Terraform Configuration**: `terraform/CONFIGURATIONS.md`
- **Application Code**: `app/main.py`
- **Bootstrap Script**: `terraform/bootstrap.sh`
- **Deployment Scripts**: `scripts/README.md`

## Support

For issues:

1. Run `./scripts/verify-instance.sh <instance-id>` for diagnostics
2. Check application logs: `journalctl -u triagebot -n 50 --no-pager`
3. Check bootstrap log: `/var/log/triagebot-bootstrap.log`
4. Consult Troubleshooting section above
5. Run recovery script if services are broken
