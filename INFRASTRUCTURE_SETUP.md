# Infrastructure Setup Summary

You now have a complete, tested infrastructure-as-code setup for deploying TriageBot. Here's what was created:

## Files Created

### Documentation
- **DEPLOYMENT.md** — Complete deployment guide with step-by-step instructions
- **terraform/CONFIGURATIONS.md** — Explains testing vs. production configurations
- **INFRASTRUCTURE_SETUP.md** — This file

### Terraform Configuration (in `terraform/`)
- **main.tf** — VPC, subnet, security group, EC2, S3, IAM
- **variables.tf** — Configuration parameters
- **outputs.tf** — Displays useful information after deployment
- **bootstrap.sh** — Runs on EC2 instance to install dependencies
- **testing.tfvars** — Pre-configured for testing (t3.medium, tinyllama, ~$35/mo)
- **production.tfvars** — Pre-configured for production (t3.large, phi3, ~$75/mo)

### Deployment Scripts (in `scripts/`)
- **deploy.sh** — Packages your local code and uploads to S3
- **decommission.sh** — Safely tears down all AWS resources

---

## What You Get

### Testing Configuration (Recommended to Start)

```bash
cd terraform
terraform apply -var-file="testing.tfvars"
```

Creates:
- **EC2 Instance:** t3.medium (2 vCPU, 4GB RAM)
- **Storage:** 20GB EBS gp3
- **Model:** tinyllama (1.1B)
- **Cost:** ~$35/month (24/7)
- **Boot time:** 2-3 minutes

Perfect for:
- Testing conversation flow
- Developing the UI
- Validating report generation
- Integration testing
- Before going live

### Production Configuration

```bash
cd terraform
terraform apply -var-file="production.tfvars"
```

Creates:
- **EC2 Instance:** t3.large (2 vCPU, 8GB RAM)
- **Storage:** 30GB EBS gp3
- **Model:** phi3 (3.8B) — can be upgraded
- **Cost:** ~$75/month (24/7)
- **Boot time:** 10-15 minutes

For:
- Real incident triage
- Better response quality
- Production use in the bank

---

## Quick Start (5 Minutes)

### Prerequisites
```bash
# 1. AWS account with credentials configured
aws configure

# 2. Terraform installed
terraform --version
```

### Deploy
```bash
# 1. Initialize
cd terraform
terraform init

# 2. Create testing infrastructure
terraform apply -var-file="testing.tfvars"

# 3. Get S3 bucket name
S3_BUCKET=$(terraform output -raw s3_bucket_name)

# 4. Deploy your code
cd .. && ./scripts/deploy.sh "$S3_BUCKET"

# 5. Check status
cd terraform && terraform output app_url
```

**Total time: 2-3 minutes**

---

## Networking

All resources are created in a single VPC with a private subnet:

```
VPC: 10.0.0.0/16
└── Private Subnet: 10.0.1.0/24
    └── EC2 Instance (no public IP)
        └── Port 8000 accessible from within VPC only
```

**Network access:**
- ✅ Works on bank private network
- ✅ Data never leaves the VPC
- ❌ Not accessible from public internet
- ❌ Requires bastion/VPN to access from outside

---

## Data Flow

1. **Local machine** → Package code, upload to S3 ✅
2. **S3** → EC2 fetches code on boot ✅
3. **EC2** → Runs FastAPI + Ollama locally ✅
4. **Ollama** → Local LLM inference (no external API calls) ✅
5. **Report** → Generated locally, displayed in UI (user copies manually) ✅

**No incident data leaves your VPC or AWS account.**

---

## Key Features

✅ **Infrastructure as Code** — Reproducible, versioned  
✅ **Automated Bootstrap** — All dependencies installed automatically  
✅ **Two Configurations** — Easily switch between testing and production  
✅ **Cost-Optimized** — Start cheap, upgrade when ready  
✅ **Private Network** — Data security and compliance  
✅ **Easy Cleanup** — `terraform destroy` removes everything  

---

## Next Steps

1. **Set up AWS:** `aws configure`
2. **Read DEPLOYMENT.md** for detailed instructions
3. **Deploy testing:** `terraform apply -var-file="testing.tfvars"`
4. **Test the app** — Try sample incidents
5. **Upgrade to production** when satisfied

---

## Support

**Terraform Commands**
```bash
cd terraform

# Plan changes
terraform plan -var-file="testing.tfvars"

# Apply changes
terraform apply -var-file="testing.tfvars"

# View current resources
terraform output

# Destroy all (CAREFUL!)
terraform destroy
```

**SSH into Instance** (requires network access or bastion)
```bash
# Get instance IP
INSTANCE_IP=$(terraform output -raw ec2_private_ip)

# SSH to instance
ssh -i your-key.pem ubuntu@$INSTANCE_IP
```

**Check Service Status** (on the instance)
```bash
# FastAPI application
sudo systemctl status triagebot
sudo journalctl -u triagebot -f

# Ollama
sudo systemctl status ollama
sudo journalctl -u ollama -f
```

---

## Cost Optimization Tips

1. **Use testing configuration** while developing (~$35/month)
2. **Stop the instance** when not in use
   ```bash
   aws ec2 stop-instances --instance-ids <id> --region ap-southeast-2
   ```
3. **Upgrade to production** only when needed (~$75/month)
4. **Monitor usage** — CloudWatch shows real consumption

**AWS Cost Explorer** (in Console) shows actual hourly costs.

---

## Troubleshooting

**Instance takes longer than 2-3 minutes to boot?**
- Model download is slow on first boot
- Check `/var/log/triagebot-bootstrap.log` on the instance

**Application won't start?**
- Ensure code was uploaded: `aws s3 ls s3://<bucket>/`
- Check logs: `sudo journalctl -u triagebot -n 50`
- Restart service: `sudo systemctl restart triagebot`

**Can't access the application?**
- You must be on the private network (bank VPN or bastion)
- Check security group: `terraform output`

**Want to destroy everything?**
```bash
terraform destroy  # Will ask for confirmation
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│  AWS Account (ap-southeast-2)                       │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  VPC (10.0.0.0/16)                          │   │
│  │                                             │   │
│  │  ┌─────────────────────────────────────┐   │   │
│  │  │  Private Subnet (10.0.1.0/24)       │   │   │
│  │  │                                     │   │   │
│  │  │  ┌───────────────────────────────┐ │   │   │
│  │  │  │  EC2 Instance (t3.medium)     │ │   │   │
│  │  │  │  ├─ FastAPI app (:8000)       │ │   │   │
│  │  │  │  ├─ Ollama                    │ │   │   │
│  │  │  │  └─ tinyllama (1.1B) model    │ │   │   │
│  │  │  └───────────────────────────────┘ │   │   │
│  │  │                                     │   │   │
│  │  │  Security Group:                    │   │   │
│  │  │  ├─ Port 8000 from VPC              │   │   │
│  │  │  └─ Outbound to all (for downloads) │   │   │
│  │  └─────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  S3 Bucket (for code staging)                      │
│  IAM Roles (EC2 → S3 access)                       │
└─────────────────────────────────────────────────────┘
```

---

## Files You Need to Know About

| File | Purpose |
|------|---------|
| `terraform/main.tf` | Core infrastructure definition |
| `terraform/bootstrap.sh` | Runs on EC2 at startup |
| `terraform/testing.tfvars` | Testing phase settings |
| `terraform/production.tfvars` | Production phase settings |
| `scripts/deploy.sh` | Deploy code from local → S3 → EC2 |
| `scripts/decommission.sh` | Delete all AWS resources |
| `DEPLOYMENT.md` | Detailed deployment guide |
| `terraform/CONFIGURATIONS.md` | Testing vs. production comparison |

---

Happy deploying! 🚀
