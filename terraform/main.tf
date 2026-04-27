terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.app_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-igw"
  }
}

# Subnet (will be public for testing)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-subnet"
  }
}

# Route table for public subnet
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.app_name}-rt"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.main.id
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Security Group
resource "aws_security_group" "app" {
  name        = "${var.app_name}-sg"
  description = "Security group for TriageBot application"
  vpc_id      = aws_vpc.main.id

  # Allow port 8000 from anywhere (testing - should be restricted in production)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (needed for package downloads, model pulling)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-sg"
  }
}

# Network Interface
resource "aws_network_interface" "app" {
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.app.id]

  tags = {
    Name = "${var.app_name}-eni"
  }
}

# S3 Bucket for code staging (for uploading local code)
resource "aws_s3_bucket" "code_bucket" {
  bucket = "${var.app_name}-code-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name = "${var.app_name}-code-bucket"
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "code_bucket" {
  bucket = aws_s3_bucket.code_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for EC2 to read from S3
resource "aws_iam_role" "ec2_role" {
  name = "${var.app_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for EC2 to read from S3
resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "${var.app_name}-ec2-s3-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.code_bucket.arn,
          "${aws_s3_bucket.code_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Attach SSM managed policy for Systems Manager access
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.app_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# EC2 Instance
resource "aws_instance" "app" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  network_interface {
    network_interface_id = aws_network_interface.app.id
    device_index         = 0
  }

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  # Root volume configuration
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
  }

  # User data script (bootstrap)
  user_data = base64encode(templatefile("${path.module}/bootstrap.sh", {
    s3_bucket = aws_s3_bucket.code_bucket.id
  }))

  monitoring = true

  tags = {
    Name = "${var.app_name}-instance"
  }

  depends_on = [
    aws_iam_role_policy.ec2_s3_policy,
    aws_internet_gateway.main,
    aws_route_table_association.main
  ]
}

# Elastic IP for public access
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.app_name}-eip"
  }

  depends_on = [aws_internet_gateway.main]
}
