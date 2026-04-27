# Testing Phase Configuration
#
# This is for initial development and testing with minimal costs.
# Use this to validate the application, conversation flow, and report generation
# before upgrading to a production-grade instance and model.
#
# Cost estimate: ~$35/month (24/7)
# - t3.medium: ~$33/month
# - 20GB storage: ~$1.70/month
#
# To use this configuration:
#   terraform apply -var-file="testing.tfvars"
#
# Or set it as the default:
#   cp testing.tfvars terraform.tfvars

aws_region       = "ap-southeast-2"
instance_type    = "t3.medium"
root_volume_size = 20

# Note: The model is configured in bootstrap.sh
# For testing: tinyllama (1.1B) - fast, lightweight, lower quality
# For production: phi3 (3.8B) or larger
