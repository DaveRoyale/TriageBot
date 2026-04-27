# TriageBot Deployment Guide

This guide walks you through deploying TriageBot to AWS using Terraform.

## Prerequisites

Before you start, you need:

1. **AWS Account** (brand new, as you mentioned)
2. **AWS CLI** installed and configured with credentials
   ```bash
   # Install AWS CLI (if not already installed)
   brew install awscli
   
   # Configure credentials
   aws configure
   # You'll be prompted for:
   #   - AWS Access Key ID
   #   - AWS Secret Access Key
   #   - Default region: ap-southeast-2
   #   - Default output format: json
   ```
3. **Terraform** installed
   ```bash
   # Install Terraform (if not already installed)
   brew install terraform
   
   # Verify installation
   terraform --version
   ```

## Quick Start (Testing Phase)

Get up and running in ~10 minutes:

```bash
# 1. Configure AWS credentials
aws configure

# 2. Set up Terraform
cd terraform && terraform init

# 3. Create testing infrastructure
terraform plan -var-file="testing.tfvars"
terraform apply -var-file="testing.tfvars"

# 4. Deploy your code
cd .. && chmod +x scripts/deploy.sh
S3_BUCKET=$(cd terraform && terraform output -raw s3_bucket_name)
./scripts/deploy.sh "$S3_BUCKET"

# 5. Check the app URL
cd terraform && terraform output app_url
```

**The instance will be ready in 2-3 minutes.** Cost: ~$35/month.

When ready to upgrade to production, see `terraform/CONFIGURATIONS.md`.

---

## Architecture Overview

The deployment creates:

```
AWS Account (ap-southeast-2)
├── VPC (10.0.0.0/16)
│   ├── Private Subnet (10.0.1.0/24)
│   │   └── EC2 Instance (t3.large, Ubuntu 22.04 LTS)
│   │       ├── FastAPI application (port 8000)
│   │       └── Ollama (LLM serving)
│   └── Security Group (port 8000 from VPC only)
└── S3 Bucket (for code staging)
```

## Step-by-Step Deployment

### 1. Prepare Your Application Code

Ensure your application has a `requirements.txt` file in the repository root:

```bash
# From the repo root
ls -la requirements.txt
# Should see the file listed
```

If you don't have one yet, create it with the necessary Python dependencies:
```
fastapi==0.104.0
uvicorn==0.24.0
python-dotenv==1.0.0
requests==2.31.0
# Add any other dependencies your app needs
```

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

You should see output like:
```
Initializing the backend...
Initializing provider plugins...
Terraform has been successfully configured!
```

### 3. Choose Your Configuration

Two pre-configured setups are available:

**Testing** (recommended for initial development):
- t3.medium instance, 20GB storage, tinyllama model
- ~$35/month
- Fast to boot (2-3 min), good for testing

**Production** (for real incident triage):
- t3.large instance, 30GB storage, phi3 model
- ~$75/month
- Higher quality responses

See `terraform/CONFIGURATIONS.md` for details.

### 4. Review the Plan

Before creating any resources, preview what will be created:

```bash
# For testing (recommended first):
terraform plan -var-file="testing.tfvars"

# Or for production:
terraform plan -var-file="production.tfvars"
```

This shows you:
- VPC, subnet, security group
- EC2 instance (t3.medium or t3.large)
- S3 bucket
- IAM roles

Review the output to make sure everything looks correct.

### 5. Apply the Infrastructure

Create the AWS resources:

```bash
# For testing:
terraform apply -var-file="testing.tfvars"

# Or for production:
terraform apply -var-file="production.tfvars"
```

Terraform will ask for confirmation:
```
Do you want to perform these actions?
```

Type `yes` to proceed.

**This takes 2-5 minutes** (longer for production due to model download). You'll see output like:
```
aws_vpc.main: Creating...
aws_vpc.main: Creation complete after 2s
...
Apply complete! Resources: 11 added, 0 changed, 0 destroyed.
```

### 6. Get the Outputs

After resources are created, Terraform shows useful information:

```bash
terraform output
```

You'll see:
- `s3_bucket_name` — where to upload your code
- `ec2_instance_id` — instance ID
- `ec2_private_ip` — private IP address
- `app_url` — where the app will run

Save these values. The S3 bucket name is needed for the next step.

### 7. Deploy Your Application Code

The EC2 instance is now running but waiting for your code. Package and upload it:

```bash
# From the repo root
chmod +x scripts/deploy.sh

# Get the S3 bucket name
S3_BUCKET=$(cd terraform && terraform output -raw s3_bucket_name)

# Deploy code
./scripts/deploy.sh "$S3_BUCKET"
```

This script:
1. Packages your app code into a zip file
2. Uploads it to S3
3. The EC2 instance downloads and extracts it

**Bootstrap time depends on configuration:**
- Testing (tinyllama): 2-3 minutes
- Production (phi3): 10-15 minutes (includes model download)

Check the bootstrap log:

```bash
# Get the instance ID
INSTANCE_ID=$(cd terraform && terraform output -raw ec2_instance_id)

# View bootstrap progress (requires AWS CLI and proper permissions)
# Logs are saved at /var/log/triagebot-bootstrap.log on the instance
```

### 8. Verify the Deployment

Once complete, the application is running on the private subnet at the IP shown in outputs:

```bash
# Get the app URL
cd terraform && terraform output app_url
# Output: http://10.0.1.x:8000
```

To test it:
- If you're on the private network: navigate to that URL in your browser
- Otherwise, you'll need to set up a bastion host or VPN to access it from outside the VPC

**Check service status:**

```bash
# SSH into the instance (if you have direct access or bastion)
sudo systemctl status triagebot  # FastAPI app
sudo systemctl status ollama      # Ollama service
```

## Configuration

### Switching Configurations

See `terraform/CONFIGURATIONS.md` for:
- **Testing** (t3.medium, tinyllama) — ~$35/month
- **Production** (t3.large, phi3) — ~$75/month

To upgrade from testing to production:
```bash
cd terraform
terraform apply -var-file="production.tfvars"
```

### Customize Settings

You can create custom configurations by editing the `.tfvars` files or creating your own:

```bash
cat > terraform/custom.tfvars << 'EOF'
aws_region       = "ap-southeast-2"
instance_type    = "t3.xlarge"      # For larger models
root_volume_size = 50
EOF

terraform apply -var-file="custom.tfvars"
```

Then edit `terraform/bootstrap.sh` to set the Ollama model:
```bash
OLLAMA_MODEL="${OLLAMA_MODEL:-mistral}"  # Change default model
```

See `terraform/CONFIGURATIONS.md` for details on model changes after deployment.

## Decommissioning

To tear down all resources and delete everything:

```bash
chmod +x scripts/decommission.sh
./scripts/decommission.sh
```

This will:
1. Prompt for confirmation
2. Delete EC2 instance, EBS volume, VPC, security groups, IAM roles
3. Delete the S3 bucket and all its contents

**CAUTION: This is irreversible.** Make sure you've backed up any important data.

Alternatively, use Terraform directly:
```bash
cd terraform
terraform destroy
```

## Troubleshooting

### Instance takes too long to boot

Ollama downloading a 3.8B model can take 5-10 minutes. Check the bootstrap log:

```bash
# If you have SSH access to the instance
tail -f /var/log/triagebot-bootstrap.log
```

### Application fails to start

Check service logs:
```bash
# On the instance
systemctl status triagebot
journalctl -u triagebot -n 50  # Last 50 lines
journalctl -u ollama -n 50
```

### "Code not yet uploaded to S3"

The bootstrap script warns about this. Re-run the deploy script:
```bash
./scripts/deploy.sh <bucket-name>

# Then restart the service on the instance
sudo systemctl restart triagebot
```

### Terraform state issues

If something goes wrong and you want to start fresh:
```bash
cd terraform
rm -rf .terraform terraform.tfstate* .terraform.lock.hcl
terraform init
```

## Costs

Two configuration options:

**Testing** (t3.medium + tinyllama):
- Compute: ~$0.046/hour (~$33/month)
- Storage (20GB EBS): ~$1.70/month
- **Total: ~$35/month**

**Production** (t3.large + phi3):
- Compute: ~$0.093/hour (~$67/month)
- Storage (30GB EBS): ~$2.55/month
- **Total: ~$75/month**

To minimize costs:
- Start with **Testing** configuration
- Upgrade to Production when ready
- Stop the instance when not in use (use AWS Console or CLI)
- Use `terraform plan` before `apply` to catch unexpected changes

See `terraform/CONFIGURATIONS.md` for details on switching.

## Next Steps

1. Test the application with sample incidents
2. Configure access (bastion host, VPN, or direct network access)
3. Set up monitoring and logging
4. Plan for production hardening (authentication, audit logging, etc.)
