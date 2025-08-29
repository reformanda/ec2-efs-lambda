# EC2-EFS-Lambda Infrastructure Deployment

This Terraform configuration creates a complete AWS infrastructure setup with:
- S3 bucket for data storage
- EFS (Elastic File System) with access points
- Lambda function for S3-EFS synchronization
- RHEL 9 EC2 instance with EFS mount
- Ansible playbook for advanced EC2 configuration

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Terraform** (>= 1.0) installed
3. **Ansible** (optional, for advanced configuration)
4. **Existing AWS resources:**
   - VPC with at least 2 subnets
   - EC2 Key Pair for SSH access

## Required AWS Permissions

Ensure your AWS credentials have permissions for:
- EC2 (instances, security groups, AMI access)
- EFS (file systems, mount targets, access points)
- S3 (bucket creation and management)
- Lambda (function creation, execution)
- IAM (role and policy management)
- CloudWatch Events

## Quick Start

### 1. Clone and Configure

```bash
git clone <your-repo-url>
cd ec2-efs-lambda
```

### 2. Set Up Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your specific values
vim terraform.tfvars
```

**Required variables to update:**
- `vpc_id`: Your existing VPC ID
- `subnet_ids`: At least 2 subnet IDs in different AZs
- `key_pair_name`: Your EC2 Key Pair name

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### 4. Get Connection Information

```bash
# View outputs
terraform output

# SSH to the EC2 instance
ssh -i /path/to/your-key.pem ec2-user@$(terraform output -raw ec2_public_ip)
```

## Advanced Configuration with Ansible

For additional EC2 configuration beyond the user data script:

### 1. Update Inventory

```bash
# Get Terraform outputs
terraform output -json > terraform_outputs.json

# Update Ansible inventory with actual values
# Edit inventory.yml with the EC2 public IP and other details
```

### 2. Run Ansible Playbook

```bash
# Test connection
ansible -i inventory.yml rhel_servers -m ping

# Run the configuration playbook
ansible-playbook -i inventory.yml configure-ec2.yml
```

## Architecture Overview

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   S3 Bucket │◄──►│    Lambda    │◄──►│     EFS     │
│             │    │   Function   │    │             │
└─────────────┘    └──────────────┘    └─────────────┘
                          │                    │
                          │                    ▼
                          │            ┌─────────────┐
                          │            │ EFS Access  │
                          │            │   Points    │
                          │            └─────────────┘
                          │                    │
                          ▼                    ▼
                   ┌──────────────┐    ┌─────────────┐
                   │   CloudWatch │    │ RHEL 9 EC2  │
                   │    Events    │    │  Instance   │
                   └──────────────┘    └─────────────┘
```

## Key Features

### EFS Configuration
- **Encrypted at rest** with AWS managed keys
- **Two access points**: one for Lambda, one for EC2
- **Mount targets** in all specified subnets
- **NFS v4.1** with TLS encryption in transit

### Lambda Function
- **Bidirectional sync** between S3 and EFS
- **Scheduled execution** via CloudWatch Events
- **VPC configuration** for EFS access
- **Comprehensive logging** and error handling

### EC2 Instance
- **RHEL 9** with latest AMI
- **amazon-efs-utils** built from source (required for RHEL 9)
- **Automatic EFS mounting** with systemd service
- **AWS CLI** pre-configured with IAM role
- **Monitoring and sync scripts** included

### Security
- **Security groups** with minimal required access
- **IAM roles** with least privilege principles
- **EFS encryption** both at rest and in transit
- **S3 bucket** with versioning and encryption

## Usage

### Manual S3-EFS Sync
```bash
# On the EC2 instance
~/sync-s3-efs.sh
```

### Monitor EFS Status
```bash
# Check mount status and usage
~/monitor-efs.sh

# Or use the alias (after Ansible setup)
efs-status
```

### EFS Directory Structure
```
/mnt/efs/
├── data/       # Main data directory (synced with S3)
├── logs/       # Application and sync logs
├── scripts/    # Custom scripts
└── backups/    # Backup files
```

## Troubleshooting

### EFS Mount Issues

1. **Check security groups**: Ensure NFS traffic (port 2049) is allowed
2. **Verify DNS resolution**: EFS requires DNS resolution in VPC
3. **Check mount targets**: Ensure mount targets exist in your subnets

```bash
# Debug mount issues
sudo mount -t efs -o tls,_netdev fs-xxxxxxxxx:/ /mnt/efs -v

# Check mount status
mountpoint /mnt/efs
df -h /mnt/efs
```

### Lambda Function Issues

1. **VPC configuration**: Lambda needs access to EFS subnets
2. **EFS access points**: Ensure access points are created properly
3. **IAM permissions**: Check Lambda execution role permissions

```bash
# Check Lambda logs
aws logs tail /aws/lambda/your-function-name --follow
```

### RHEL 9 Specific Issues

1. **amazon-efs-utils build**: If build fails, check required packages
2. **Firewall rules**: RHEL 9 may have stricter firewall rules

```bash
# Check if efs-utils is installed correctly
rpm -qa | grep amazon-efs-utils

# Verify EFS helper is available
which mount.efs
```

## Customization

### Modify Sync Schedule
Edit the `sync_schedule` variable in `terraform.tfvars`:
```hcl
sync_schedule = "rate(30 minutes)"  # Every 30 minutes
# or
sync_schedule = "cron(0 2 * * ? *)"  # Daily at 2 AM
```

### Add Custom Lambda Logic
Modify `lambda_function.py` to add custom processing logic:
- File filtering
- Data transformation
- Custom notifications
- Integration with other AWS services

### EC2 Instance Customization
- Modify `user_data.sh` for additional software installation
- Update the Ansible playbook for complex configurations
- Add custom monitoring or backup scripts

## Cost Considerations

- **EFS**: Charged for storage used and throughput
- **Lambda**: Pay per request and execution time
- **EC2**: Standard instance charges
- **Data Transfer**: Between EFS and Lambda in same AZ is free

## Security Best Practices

1. **Restrict SSH access**: Update `ssh_cidr_blocks` to your IP range
2. **Use VPC endpoints**: For S3 access to avoid internet routing
3. **Enable CloudTrail**: For API call logging
4. **Regular updates**: Keep EC2 instance packages updated
5. **Backup strategy**: Consider EFS backup policies

## Support

For issues:
1. Check AWS service limits and quotas
2. Review CloudWatch logs for Lambda and EC2
3. Verify IAM permissions and security groups
4. Consult AWS EFS and Lambda documentation

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Note**: This will delete all data in S3 and EFS. Ensure you have backups if needed.