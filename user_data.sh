#!/bin/bash
# user_data.sh - EC2 User Data Script for RHEL 9

# Set variables from Terraform template
EFS_ID="${efs_id}"
AWS_REGION="${aws_region}"
S3_BUCKET="${s3_bucket}"

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting EC2 initialization at $(date)"

# Update system
dnf update -y

# Install required packages
dnf install -y \
    nfs-utils \
    aws-cli \
    python3 \
    python3-pip \
    git \
    htop \
    tree \
    wget \
    curl \
    gcc \
    make \
    rpm-build \
    rpm-devel \
    libtool \
    systemd-devel \
    openssl-devel \
    cargo \
    rust

# Build and install amazon-efs-utils from source for RHEL 9
echo "Building amazon-efs-utils from source..."
cd /tmp
git clone https://github.com/aws/efs-utils
cd efs-utils

# Build the RPM package
make rpm

# Install the built RPM
rpm -ivh build/amazon-efs-utils*rpm

echo "amazon-efs-utils installed successfully"

# Create mount point
mkdir -p /mnt/efs

# Create fstab entry for EFS (using TLS encryption)
echo "${EFS_ID}.efs.${AWS_REGION}.amazonaws.com:/ /mnt/efs efs defaults,_netdev,tls" >> /etc/fstab

# Mount EFS with TLS encryption
mount -t efs -o tls ${EFS_ID}:/ /mnt/efs

# Verify mount
if mountpoint -q /mnt/efs; then
    echo "EFS mounted successfully at /mnt/efs"
    df -h /mnt/efs
else
    echo "Failed to mount EFS"
    exit 1
fi

# Set proper permissions
chown ec2-user:ec2-user /mnt/efs
chmod 755 /mnt/efs

# Create directory structure
mkdir -p /mnt/efs/data
mkdir -p /mnt/efs/logs
mkdir -p /mnt/efs/scripts

# Create a test file
echo "EFS mount successful at $(date)" > /mnt/efs/logs/mount-test.log

# Install additional Python packages for data processing
pip3 install --user boto3 pandas numpy

# Create a simple sync script for manual S3-EFS sync
cat > /home/ec2-user/sync-s3-efs.sh << 'EOF'
#!/bin/bash
# Simple script to sync S3 bucket with EFS

S3_BUCKET="__S3_BUCKET__"
EFS_PATH="/mnt/efs/data"

echo "Starting S3 to EFS sync at $(date)"

# Sync from S3 to EFS
aws s3 sync s3://${S3_BUCKET} ${EFS_PATH}

echo "Sync completed at $(date)"
EOF

# Replace placeholder with actual bucket name
sed -i "s/__S3_BUCKET__/${S3_BUCKET}/g" /home/ec2-user/sync-s3-efs.sh

# Make script executable
chmod +x /home/ec2-user/sync-s3-efs.sh
chown ec2-user:ec2-user /home/ec2-user/sync-s3-efs.sh

# Update systemd service to use TLS
cat > /etc/systemd/system/efs-mount.service << EOF
[Unit]
Description=EFS Mount Service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/mount -t efs -o tls ${EFS_ID}:/ /mnt/efs
ExecStop=/bin/umount /mnt/efs
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable efs-mount.service

# Create a monitoring script
cat > /home/ec2-user/monitor-efs.sh << 'EOF'
#!/bin/bash
# Monitor EFS mount and usage

echo "=== EFS Mount Status ==="
mountpoint -q /mnt/efs && echo "✓ EFS is mounted" || echo "✗ EFS is NOT mounted"

echo -e "\n=== EFS Disk Usage ==="
df -h /mnt/efs 2>/dev/null || echo "EFS not available"

echo -e "\n=== EFS Directory Contents ==="
ls -la /mnt/efs/ 2>/dev/null || echo "Cannot access EFS directory"

echo -e "\n=== Recent EFS Activity ==="
find /mnt/efs -type f -mtime -1 2>/dev/null | head -10 || echo "No recent files found"
EOF

chmod +x /home/ec2-user/monitor-efs.sh
chown ec2-user:ec2-user /home/ec2-user/monitor-efs.sh

# Create a simple web server to show EFS status (optional)
cat > /home/ec2-user/efs-status-server.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import subprocess
from datetime import datetime

class EFSStatusHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            
            # Get EFS status
            try:
                mount_check = subprocess.run(['mountpoint', '/mnt/efs'], 
                                           capture_output=True, text=True)
                is_mounted = mount_check.returncode == 0
                
                df_output = subprocess.run(['df', '-h', '/mnt/efs'], 
                                         capture_output=True, text=True)
                disk_usage = df_output.stdout if df_output.returncode == 0 else "N/A"
                
            except Exception as e:
                is_mounted = False
                disk_usage = str(e)
            
            html = f"""
            <!DOCTYPE html>
            <html>
            <head>
                <title>EFS Status</title>
                <meta http-equiv="refresh" content="30">
                <style>
                    body {{ font-family: Arial, sans-serif; margin: 40px; }}
                    .status {{ padding: 20px; border-radius: 5px; margin: 10px 0; }}
                    .mounted {{ background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; }}
                    .unmounted {{ background-color: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }}
                    pre {{ background-color: #f8f9fa; padding: 10px; border-radius: 3px; }}
                </style>
            </head>
            <body>
                <h1>EFS Status Dashboard</h1>
                <div class="status {'mounted' if is_mounted else 'unmounted'}">
                    <h2>Mount Status: {'✓ MOUNTED' if is_mounted else '✗ NOT MOUNTED'}</h2>
                </div>
                <h3>Disk Usage:</h3>
                <pre>{disk_usage}</pre>
                <p><small>Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</small></p>
                <p><small>Auto-refresh every 30 seconds</small></p>
            </body>
            </html>
            """
            self.wfile.write(html.encode())
        
        elif self.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            try:
                mount_check = subprocess.run(['mountpoint', '/mnt/efs'], 
                                           capture_output=True, text=True)
                is_mounted = mount_check.returncode == 0
                
                status = {
                    'mounted': is_mounted,
                    'timestamp': datetime.now().isoformat(),
                    'mount_point': '/mnt/efs'
                }
            except Exception as e:
                status = {
                    'mounted': False,
                    'error': str(e),
                    'timestamp': datetime.now().isoformat()
                }
            
            self.wfile.write(json.dumps(status).encode())

if __name__ == "__main__":
    PORT = 8080
    with socketserver.TCPServer(("", PORT), EFSStatusHandler) as httpd:
        print(f"EFS Status server running on port {PORT}")
        httpd.serve_forever()
EOF

chmod +x /home/ec2-user/efs-status-server.py
chown ec2-user:ec2-user /home/ec2-user/efs-status-server.py

# Create systemd service for the EFS status web server
cat > /etc/systemd/system/efs-status-web.service << EOF
[Unit]
Description=EFS Status Web Server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/efs-status-server.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the web service
systemctl enable efs-status-web.service
systemctl start efs-status-web.service

# Create a simple health check script
cat > /home/ec2-user/health-check.sh << 'EOF'
#!/bin/bash
# Health check script for EFS and services

echo "=== System Health Check ($(date)) ==="

# Check EFS mount
if mountpoint -q /mnt/efs; then
    echo "✓ EFS Mount: OK"
else
    echo "✗ EFS Mount: FAILED"
    # Try to remount
    echo "Attempting to remount EFS..."
    mount -t efs -o tls ${EFS_ID}:/ /mnt/efs
fi

# Check EFS connectivity
if [ -w /mnt/efs ]; then
    echo "✓ EFS Write Access: OK"
    echo "Health check at $(date)" > /mnt/efs/logs/health-check.log
else
    echo "✗ EFS Write Access: FAILED"
fi

# Check AWS CLI
if aws sts get-caller-identity &>/dev/null; then
    echo "✓ AWS CLI: OK"
else
    echo "✗ AWS CLI: FAILED"
fi

# Check web service
if systemctl is-active --quiet efs-status-web.service; then
    echo "✓ EFS Status Web Service: OK"
else
    echo "✗ EFS Status Web Service: FAILED"
    systemctl restart efs-status-web.service
fi

echo "=== End Health Check ==="
EOF

chmod +x /home/ec2-user/health-check.sh
chown ec2-user:ec2-user /home/ec2-user/health-check.sh

# Set up cron job for health checks
echo "*/15 * * * * /home/ec2-user/health-check.sh >> /mnt/efs/logs/health-check.log 2>&1" | crontab -u ec2-user -

# Create bash aliases for convenience
cat >> /home/ec2-user/.bashrc << 'EOF'

# EFS Management Aliases
alias efs-status='/home/ec2-user/monitor-efs.sh'
alias efs-sync='/home/ec2-user/sync-s3-efs.sh'
alias efs-health='/home/ec2-user/health-check.sh'
alias efs-logs='tail -f /mnt/efs/logs/*.log'
alias efs-space='df -h /mnt/efs'

# Quick navigation
alias cdefs='cd /mnt/efs'
alias cdata='cd /mnt/efs/data'
alias clogs='cd /mnt/efs/logs'

echo "EFS aliases loaded: efs-status, efs-sync, efs-health, efs-logs, efs-space"
EOF

# Set ownership
chown ec2-user:ec2-user /home/ec2-user/.bashrc

# Final test and status
echo "=== Final Setup Verification ==="
echo "EFS Mount Status:"
mountpoint /mnt/efs && echo "✓ EFS Mounted" || echo "✗ EFS Mount Failed"

echo "Directory Structure:"
ls -la /mnt/efs/

echo "Services Status:"
systemctl is-enabled efs-mount.service && echo "✓ EFS Mount Service Enabled" || echo "✗ EFS Mount Service Failed"
systemctl is-active efs-status-web.service && echo "✓ EFS Status Web Service Running" || echo "✗ EFS Status Web Service Failed"

echo "Available Commands:"
echo "  efs-status  - Check EFS mount status and usage"
echo "  efs-sync    - Sync with S3 bucket"
echo "  efs-health  - Run health check"
echo "  efs-logs    - View logs"

echo "Web Interface:"
echo "  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"

echo "EC2 initialization completed at $(date)"