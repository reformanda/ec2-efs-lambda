# terraform.tfvars.example
# Copy this file to terraform.tfvars and update the values

# AWS Configuration
aws_region = "us-west-1"

# Project Configuration
project_name = "my-efs-project"

# Network Configuration (REQUIRED - update these with your actual values)
vpc_id = "vpc-bdd5cddf"  # Your existing VPC ID
subnet_ids = [
  "subnet-613d1027",     # Your first subnet ID
  "subnet-1cfe1c79"      # Your second subnet ID
]

# EC2 Configuration
key_pair_name = "rhel9-us-west-1"     # Your existing EC2 Key Pair name
instance_type = "t3.medium"       # EC2 instance type

# Security Configuration
ssh_cidr_blocks = [
  "10.0.0.0/8",          # Allow SSH from private networks
  "98.152.30.138/32"     # Replace with your public IP
]

# Lambda Configuration
sync_schedule = "rate(1 hour)"     # Run sync every hour

# Tagging
common_tags = {
  Project     = "EFS-S3-Lambda-Sync"
  Environment = "development"
  Owner       = "your-name"
  ManagedBy   = "terraform"
  CostCenter  = "engineering"
}