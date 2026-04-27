# Production Phase Configuration
#
# This configuration uses a larger instance and model for production use.
# Use this when you've tested the application and are ready for real incident triage.
#
# Cost estimate: ~$75/month (24/7)
# - t3.large: ~$67/month
# - 30GB storage: ~$2.55/month
#
# To use this configuration:
#   terraform apply -var-file="production.tfvars"
#
# Then update the model in bootstrap.sh if needed:
#   Edit: Environment="OLLAMA_MODEL=tinyllama"
#   To:   Environment="OLLAMA_MODEL=phi3"
#   Then: sudo systemctl restart triagebot

aws_region       = "ap-southeast-2"
instance_type    = "t3.large"
root_volume_size = 30

# Note: To change the model from tinyllama to phi3:
# 1. SSH into the instance
# 2. Edit: sudo nano /etc/systemd/system/triagebot.service
# 3. Change: Environment="OLLAMA_MODEL=tinyllama"
#    To:     Environment="OLLAMA_MODEL=phi3"
# 4. Pull the model: sudo -u ollama /usr/bin/ollama pull phi3
# 5. Restart: sudo systemctl restart triagebot
