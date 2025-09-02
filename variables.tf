variable "route_table_ids" {
  description = "List of route table IDs for the VPC S3 endpoint. Should include all route tables for subnets that need S3 access."
  type        = list(string)
}
# variables.tf - Variable definitions

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ec2-efs-lambda"
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for EFS mount targets and EC2"
  type        = list(string)
  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs must be provided."
  }
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "sync_schedule" {
  description = "CloudWatch Events schedule expression for S3-EFS sync"
  type        = string
  default     = "rate(1 hour)"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "EC2-EFS-Lambda"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}