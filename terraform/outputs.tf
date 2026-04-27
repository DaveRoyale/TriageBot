output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.app.id
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "ec2_private_ip" {
  description = "EC2 instance private IP"
  value       = aws_instance.app.private_ip
}

output "ec2_public_ip" {
  description = "EC2 instance public IP (Elastic IP for testing)"
  value       = aws_eip.app.public_ip
}

output "s3_bucket_name" {
  description = "S3 bucket name for code staging"
  value       = aws_s3_bucket.code_bucket.id
}

output "app_url" {
  description = "Application URL (public IP for testing)"
  value       = "http://${aws_eip.app.public_ip}:8000"
}

output "app_url_private" {
  description = "Application URL (private IP - only accessible from within VPC)"
  value       = "http://${aws_instance.app.private_ip}:8000"
}

output "deployment_command" {
  description = "Command to deploy code to S3"
  value       = "aws s3 cp triagebot-code.zip s3://${aws_s3_bucket.code_bucket.id}/"
}
