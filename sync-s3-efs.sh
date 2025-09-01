#!/bin/bash
# sync-s3-efs.sh - S3-EFS Synchronization Script
# This script syncs data between S3 bucket and EFS mount

# Configuration - these will be set by Terraform/user data script
S3_BUCKET="${s3_bucket}"
EFS_PATH="/mnt/efs/www"
LOG_FILE="/mnt/efs/logs/sync-$(date +%Y%m%d).log"
LOCK_FILE="/tmp/s3-efs-sync.lock"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [[ "$DEBUG" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log_message "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        log_message "ERROR" "AWS CLI is not installed"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_message "ERROR" "AWS CLI not configured or no permissions"
        return 1
    fi
    
    # Check if S3 bucket exists and is accessible
    if ! aws s3 ls "s3://$S3_BUCKET" &>/dev/null; then
        log_message "ERROR" "Cannot access S3 bucket: $S3_BUCKET"
        return 1
    fi
    
    # Check if EFS is mounted
    if ! mountpoint -q /mnt/efs; then
        log_message "ERROR" "EFS is not mounted at /mnt/efs"
        return 1
    fi
    
    # Ensure directories exist
    mkdir -p "$EFS_PATH"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_message "INFO" "Prerequisites check passed"
    return 0
}

# Function to acquire lock
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_message "WARN" "Sync already running (PID: $pid). Exiting."
            return 1
        else
            log_message "WARN" "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    log_message "INFO" "Lock acquired (PID: $$)"
    return 0
}

# Function to release lock
release_lock() {
    rm -f "$LOCK_FILE"
    log_message "INFO" "Lock released"
}

# Function to sync from S3 to EFS
sync_s3_to_efs() {
    log_message "INFO" "Starting S3 to EFS sync..."
    log_message "INFO" "Source: s3://$S3_BUCKET"
    log_message "INFO" "Destination: $EFS_PATH"
    
    local start_time=$(date +%s)
    
    # Count objects before sync
    local s3_objects=$(aws s3 ls "s3://$S3_BUCKET" --recursive 2>/dev/null | wc -l)
    log_message "INFO" "S3 bucket contains $s3_objects objects"
    
    # Perform sync with detailed logging
    if aws s3 sync "s3://$S3_BUCKET" "$EFS_PATH" \
        --delete \
        --no-progress \
        --cli-read-timeout 300 \
        --cli-connect-timeout 60 2>&1 | tee -a "$LOG_FILE"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_message "INFO" "S3 to EFS sync completed successfully in ${duration}s"
        
        # Count files after sync
        local local_files=$(find "$EFS_PATH" -type f 2>/dev/null | wc -l)
        log_message "INFO" "EFS now contains $local_files files"
        
        return 0
    else
        log_message "ERROR" "S3 to EFS sync failed"
        return 1
    fi
}

# Function to sync from EFS to S3
sync_efs_to_s3() {
    log_message "INFO" "Starting EFS to S3 sync..."
    log_message "INFO" "Source: $EFS_PATH"
    log_message "INFO" "Destination: s3://$S3_BUCKET"
    
    local start_time=$(date +%s)
    
    # Count files before sync
    local local_files=$(find "$EFS_PATH" -type f 2>/dev/null | wc -l)
    log_message "INFO" "EFS contains $local_files files"
    
    # Perform sync with detailed logging
    if aws s3 sync "$EFS_PATH" "s3://$S3_BUCKET" \
        --delete \
        --no-progress \
        --cli-read-timeout 300 \
        --cli-connect-timeout 60 2>&1 | tee -a "$LOG_FILE"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_message "INFO" "EFS to S3 sync completed successfully in ${duration}s"
        
        # Count objects after sync
        local s3_objects=$(aws s3 ls "s3://$S3_BUCKET" --recursive 2>/dev/null | wc -l)
        log_message "INFO" "S3 bucket now contains $s3_objects objects"
        
        return 0
    else
        log_message "ERROR" "EFS to S3 sync failed"
        return 1
    fi
}

# Function to show disk usage
show_usage() {
    log_message "INFO" "=== Storage Usage ==="
    
    # EFS usage
    local efs_usage=$(df -h /mnt/efs 2>/dev/null | tail -1)
    log_message "INFO" "EFS Usage: $efs_usage"
    
    # S3 bucket size
    log_message "INFO" "Calculating S3 bucket size..."
    local s3_size=$(aws s3 ls "s3://$S3_BUCKET" --recursive --human-readable --summarize 2>/dev/null | grep "Total Size" | awk '{print $3 " " $4}')
    log_message "INFO" "S3 Bucket Size: ${s3_size:-"Unable to calculate"}"
    
    # Local directory size
    local local_size=$(du -sh "$EFS_PATH" 2>/dev/null | cut -f1)
    log_message "INFO" "EFS Data Directory Size: ${local_size:-"Unable to calculate"}"
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

COMMANDS:
    s3-to-efs       Sync from S3 to EFS (default)
    efs-to-s3       Sync from EFS to S3
    bidirectional   Sync both directions
    status          Show sync status and usage
    help            Show this help message

OPTIONS:
    -b, --bucket    S3 bucket name (overrides default)
    -p, --path      EFS path (overrides default: /mnt/efs/data)
    -l, --log       Log file path (overrides default)
    -d, --debug     Enable debug logging
    -n, --dry-run   Show what would be synced without actually syncing
    -q, --quiet     Suppress output (except errors)

EXAMPLES:
    $0                          # Sync from S3 to EFS
    $0 efs-to-s3               # Sync from EFS to S3
    $0 bidirectional           # Sync both directions
    $0 -d s3-to-efs           # Sync with debug logging
    $0 -n efs-to-s3           # Dry run EFS to S3
    $0 --bucket my-bucket      # Use different bucket
    
ENVIRONMENT VARIABLES:
    S3_BUCKET       S3 bucket name
    EFS_PATH        EFS mount path
    DEBUG           Enable debug logging (true/false)
EOF
}

# Function to perform dry run
dry_run() {
    local direction=$1
    log_message "INFO" "=== DRY RUN MODE ===" 
    
    case $direction in
        "s3-to-efs")
            log_message "INFO" "Would sync from s3://$S3_BUCKET to $EFS_PATH"
            aws s3 sync "s3://$S3_BUCKET" "$EFS_PATH" --dryrun 2>&1 | tee -a "$LOG_FILE"
            ;;
        "efs-to-s3")
            log_message "INFO" "Would sync from $EFS_PATH to s3://$S3_BUCKET"
            aws s3 sync "$EFS_PATH" "s3://$S3_BUCKET" --dryrun 2>&1 | tee -a "$LOG_FILE"
            ;;
        "bidirectional")
            log_message "INFO" "Would sync bidirectionally"
            log_message "INFO" "S3 to EFS:"
            aws s3 sync "s3://$S3_BUCKET" "$EFS_PATH" --dryrun 2>&1 | tee -a "$LOG_FILE"
            log_message "INFO" "EFS to S3:"
            aws s3 sync "$EFS_PATH" "s3://$S3_BUCKET" --dryrun 2>&1 | tee -a "$LOG_FILE"
            ;;
    esac
}

# Function to show sync status
show_status() {
    log_message "INFO" "=== Sync Status ==="
    log_message "INFO" "S3 Bucket: $S3_BUCKET"
    log_message "INFO" "EFS Path: $EFS_PATH"
    log_message "INFO" "Log File: $LOG_FILE"
    
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_message "INFO" "Sync Status: RUNNING (PID: $pid)"
        else
            log_message "INFO" "Sync Status: STALE LOCK (removing)"
            rm -f "$LOCK_FILE"
        fi
    else
        log_message "INFO" "Sync Status: IDLE"
    fi
    
    # Show last sync information
    if [ -f "$LOG_FILE" ]; then
        local last_sync=$(tail -20 "$LOG_FILE" | grep "sync completed successfully" | tail -1)
        if [ -n "$last_sync" ]; then
            log_message "INFO" "Last Successful Sync: $last_sync"
        fi
    fi
    
    show_usage
}

# Trap to ensure lock is released on exit
trap 'release_lock; exit' SIGINT SIGTERM EXIT

# Parse command line arguments
DRY_RUN=false
QUIET=false
COMMAND="s3-to-efs"

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bucket)
            S3_BUCKET="$2"
            shift 2
            ;;
        -p|--path)
            EFS_PATH="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        s3-to-efs|efs-to-s3|bidirectional|status|help)
            COMMAND="$1"
            shift
            ;;
        *)
            log_message "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Redirect output if quiet mode
if [[ "$QUIET" == "true" ]]; then
    exec 1>/dev/null
fi

# Main execution
log_message "INFO" "=== S3-EFS Sync Started ($(date)) ==="
log_message "INFO" "Command: $COMMAND"
log_message "INFO" "S3 Bucket: $S3_BUCKET"
log_message "INFO" "EFS Path: $EFS_PATH"

# Handle help command
if [[ "$COMMAND" == "help" ]]; then
    show_help
    exit 0
fi

# Handle status command
if [[ "$COMMAND" == "status" ]]; then
    show_status
    exit 0
fi

# Check prerequisites for sync commands
if ! check_prerequisites; then
    log_message "ERROR" "Prerequisites check failed"
    exit 1
fi

# Handle dry run
if [[ "$DRY_RUN" == "true" ]]; then
    dry_run "$COMMAND"
    exit 0
fi

# Acquire lock for actual sync operations
if ! acquire_lock; then
    exit 1
fi

# Execute the requested command
case $COMMAND in
    "s3-to-efs")
        if sync_s3_to_efs; then
            log_message "INFO" "=== S3-EFS Sync Completed Successfully ($(date)) ==="
            exit 0
        else
            log_message "ERROR" "=== S3-EFS Sync Failed ($(date)) ==="
            exit 1
        fi
        ;;
    "efs-to-s3")
        if sync_efs_to_s3; then
            log_message "INFO" "=== EFS-S3 Sync Completed Successfully ($(date)) ==="
            exit 0
        else
            log_message "ERROR" "=== EFS-S3 Sync Failed ($(date)) ==="
            exit 1
        fi
        ;;
    "bidirectional")
        log_message "INFO" "Starting bidirectional sync..."
        success=true
        
        if ! sync_s3_to_efs; then
            success=false
        fi
        
        if ! sync_efs_to_s3; then
            success=false
        fi
        
        if [[ "$success" == "true" ]]; then
            log_message "INFO" "=== Bidirectional Sync Completed Successfully ($(date)) ==="
            exit 0
        else
            log_message "ERROR" "=== Bidirectional Sync Failed ($(date)) ==="
            exit 1
        fi
        ;;
    *)
        log_message "ERROR" "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac