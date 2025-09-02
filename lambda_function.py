import json
import boto3
import os
import logging
from datetime import datetime
import shutil
from pathlib import Path

# Configure logging
logger = logging.getLogger()
logger.setLevel(getattr(logging, os.environ.get('LOG_LEVEL', 'INFO')))

# Initialize AWS clients
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to sync data between S3 and EFS
    """
    try:
        bucket_name = os.environ['S3_BUCKET']
        efs_path = os.environ['EFS_PATH']
        
        logger.info(f"Starting S3-EFS sync for bucket: {bucket_name}")
        logger.info(f"EFS mount path: {efs_path}")
        
        # Ensure EFS directory exists
        Path(efs_path).mkdir(parents=True, exist_ok=True)
        
        # Get list of objects in S3 bucket
        response = s3_client.list_objects_v2(Bucket=bucket_name)
        
        if 'Contents' not in response:
            logger.info("No objects found in S3 bucket")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No objects to sync',
                    'timestamp': datetime.utcnow().isoformat()
                })
            }
        

        synced_files = []
        errors = []

        for obj in response['Contents']:
            key = obj['Key']
            local_path = os.path.join(efs_path, key)

            try:
                # Create directory structure if needed
                local_dir = os.path.dirname(local_path)
                if local_dir:
                    Path(local_dir).mkdir(parents=True, exist_ok=True)

                # Check if file exists and compare modification times
                should_download = True
                if os.path.exists(local_path):
                    local_mtime = datetime.fromtimestamp(os.path.getmtime(local_path))
                    s3_mtime = obj['LastModified'].replace(tzinfo=None)

                    if local_mtime >= s3_mtime:
                        should_download = False
                        logger.debug(f"Skipping {key} - local file is up to date")

                if should_download:
                    logger.info(f"Downloading {key} to {local_path}")
                    s3_client.download_file(bucket_name, key, local_path)
                    synced_files.append(key)

            except Exception as e:
                error_msg = f"Error syncing {key}: {str(e)}"
                logger.error(error_msg)
                errors.append(error_msg)

        result = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sync completed',
                'downloaded_files': len(synced_files),
                'errors': len(errors),
                'timestamp': datetime.utcnow().isoformat(),
                'details': {
                    'downloaded': synced_files,
                    'errors': errors
                }
            })
        }

        logger.info(f"Sync completed. Downloaded: {len(synced_files)}, Errors: {len(errors)}")
        return result
        
    except Exception as e:
        logger.error(f"Lambda function error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def sync_efs_to_s3(bucket_name, efs_path):
    """
    Sync files from EFS to S3 (upload new/modified files)
    """
    uploaded_files = []
    
    try:
        # Walk through EFS directory
        for root, dirs, files in os.walk(efs_path):
            for file in files:
                local_path = os.path.join(root, file)
                
                # Calculate S3 key (relative path from EFS mount point)
                relative_path = os.path.relpath(local_path, efs_path)
                s3_key = relative_path.replace('\\', '/')  # Ensure forward slashes for S3
                
                try:
                    # Check if file exists in S3 and compare modification times
                    should_upload = True
                    try:
                        response = s3_client.head_object(Bucket=bucket_name, Key=s3_key)
                        s3_mtime = response['LastModified'].replace(tzinfo=None)
                        local_mtime = datetime.fromtimestamp(os.path.getmtime(local_path))
                        
                        if local_mtime <= s3_mtime:
                            should_upload = False
                            logger.debug(f"Skipping upload of {s3_key} - S3 file is up to date")
                            
                    except s3_client.exceptions.NoSuchKey:
                        # File doesn't exist in S3, so upload it
                        pass
                    
                    if should_upload:
                        logger.info(f"Uploading {local_path} to s3://{bucket_name}/{s3_key}")
                        s3_client.upload_file(local_path, bucket_name, s3_key)
                        uploaded_files.append(s3_key)
                        
                except Exception as e:
                    logger.error(f"Error uploading {local_path}: {str(e)}")
                    
    except Exception as e:
        logger.error(f"Error walking EFS directory: {str(e)}")
    
    return uploaded_files

def get_file_size(file_path):
    """Get file size in a human-readable format"""
    size = os.path.getsize(file_path)
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"