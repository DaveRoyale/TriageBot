# Terraform Configurations

This directory includes two pre-configured setups: **Testing** and **Production**.

## Testing Configuration

**File:** `testing.tfvars`

**When to use:** Initial development and testing phase
- Validate conversation flow
- Test report generation
- Try different incident types
- Debug the application

**Specs:**
- Instance: `t3.medium` (2 vCPU, 4GB RAM)
- Storage: 20GB EBS gp3
- Model: `tinyllama` (1.1B, very fast)
- Cost: ~$35/month (24/7)

**Use it:**
```bash
terraform apply -var-file="testing.tfvars"
```

**Trade-offs:**
- ✅ Cheap and fast to start
- ✅ Quick response times (1-3 seconds)
- ✅ Boots in 2-3 minutes
- ❌ Lower quality responses (but good enough for testing)
- ❌ Limited context understanding (1.1B parameters)

---

## Production Configuration

**File:** `production.tfvars`

**When to use:** Real incident triage after testing is complete
- Run the application in a bank environment
- Handle real compliance incidents
- Provide consistent, high-quality responses

**Specs:**
- Instance: `t3.large` (2 vCPU, 8GB RAM)
- Storage: 30GB EBS gp3
- Model: `phi3` (3.8B) or larger
- Cost: ~$75/month (24/7) with phi3

**Use it:**
```bash
terraform apply -var-file="production.tfvars"
```

**Trade-offs:**
- ✅ Higher quality responses
- ✅ Better context understanding
- ✅ More robust for real incidents
- ❌ More expensive
- ❌ Slower first boot (~10 minutes for model download)

---

## Switching Between Configurations

### Start with Testing

```bash
# Initialize Terraform
terraform init

# Create testing infrastructure
terraform apply -var-file="testing.tfvars"

# Verify deployment
terraform output app_url
```

### Later: Upgrade to Production

When you're satisfied with testing and ready for production:

```bash
# Update infrastructure
terraform apply -var-file="production.tfvars"
```

This will:
1. Stop the t3.medium instance
2. Create a new t3.large instance
3. Keep the same VPC, subnet, security group, and code
4. Start with `tinyllama` (you can manually upgrade the model)

The downtime is ~5 minutes.

### Upgrade the Model (Optional)

After upgrading to t3.large, you can switch to a better model:

**SSH into the instance:**
```bash
# From the AWS Console, connect via Systems Manager Session Manager
# Or set up a bastion host / VPN
```

**Upgrade the model:**
```bash
# Pull the new model
sudo -u ollama /usr/bin/ollama pull phi3

# Edit the systemd service
sudo nano /etc/systemd/system/triagebot.service

# Change this line:
#   Environment="OLLAMA_MODEL=tinyllama"
# To this:
#   Environment="OLLAMA_MODEL=phi3"

# Save (Ctrl+O, Enter, Ctrl+X)

# Restart the service
sudo systemctl restart triagebot
```

---

## No Configuration File (Default)

If you run `terraform apply` without specifying a `-var-file`:

Terraform will use default values from `variables.tf`:
- Instance: `t3.large` (the production spec)
- Storage: 30GB
- Model: `tinyllama` (for safety)

**Recommendation:** Explicitly use one of the two configuration files to be clear about your intent.

---

## Comparing Costs

| | Testing | Production |
|---|---------|-----------|
| Instance | t3.medium ($0.0464/hr) | t3.large ($0.0928/hr) |
| Storage (20GB/30GB) | $1.70/mo | $2.55/mo |
| Model | tinyllama (1.1B) | phi3 (3.8B) |
| **Monthly cost** | ~$35 | ~$75 |
| Boot time | 2-3 min | 10-15 min* |
| Response time | 1-3 sec | 2-5 sec |
| Quality | Basic | Good |

*includes model download on first boot

---

## Terraform State

Terraform stores the current infrastructure state in:
- `terraform.tfstate` (do not commit to git)
- `.terraform/` directory

When you switch configurations, Terraform automatically detects differences and only changes what's needed.

**Important:** Keep `terraform.tfstate` safe—it contains references to your AWS resources. Losing it makes cleanup harder.

---

## Decommissioning

To delete all resources (both testing and production):

```bash
terraform destroy
```

Or use the provided script:
```bash
../scripts/decommission.sh
```

This deletes:
- EC2 instances
- EBS volumes
- VPC, subnet, security groups
- S3 bucket (and all contents)
- IAM roles and policies

**Warning:** This is irreversible.
