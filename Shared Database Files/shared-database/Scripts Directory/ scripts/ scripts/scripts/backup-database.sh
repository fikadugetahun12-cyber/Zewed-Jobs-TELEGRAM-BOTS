#!/bin/bash

# ZewedJobs Database Backup Script
# Creates compressed backup of database and application files

set -e

# Configuration
BACKUP_DIR="/var/www/zewedjobs/shared-database/backups"
DB_NAME="zewedjobs_admin"
DB_USER="root"
APP_DIR="/var/www/zewedjobs"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30
LOG_FILE="/var/log/zewedjobs_backup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error function
error() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root"
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo ""
echo "💾 ZewedJobs Backup Script"
echo "=========================="
echo "Backup started at: $(date)"
echo "Backup directory: $BACKUP_DIR"
echo ""

# Step 1: Backup Database
log "1. Backing up database: $DB_NAME"
DB_BACKUP_FILE="$BACKUP_DIR/db_backup_${DATE}.sql.gz"

# Get database password from config or use default
if [ -f "$APP_DIR/admin-panel/config/.env" ]; then
    DB_PASS=$(grep DB_PASS "$APP_DIR/admin-panel/config/.env" | cut -d'=' -f2)
else
    DB_PASS=""
fi

if [ -z "$DB_PASS" ]; then
    # Try to get from Telegram bot config
    if [ -f "$APP_DIR/telegram-bot/.env" ]; then
        DB_PASS=$(grep DB_PASS "$APP_DIR/telegram-bot/.env" | cut -d'=' -f2)
    fi
fi

# Perform database backup
if mysqldump -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --routines \
    --triggers \
    --events \
    "$DB_NAME" | gzip > "$DB_BACKUP_FILE"; then
    
    DB_SIZE=$(du -h "$DB_BACKUP_FILE" | cut -f1)
    log "${GREEN}✓ Database backup completed: $DB_BACKUP_FILE ($DB_SIZE)${NC}"
else
    error "Database backup failed"
fi

# Step 2: Backup Application Files
log "2. Backing up application files"
APP_BACKUP_FILE="$BACKUP_DIR/app_backup_${DATE}.tar.gz"

# Create tar archive excluding large/unnecessary files
tar -czf "$APP_BACKUP_FILE" \
    --exclude="*/venv" \
    --exclude="*/node_modules" \
    --exclude="*.log" \
    --exclude="*.pyc" \
    --exclude="__pycache__" \
    --exclude="backups/*" \
    -C "$(dirname "$APP_DIR")" "$(basename "$APP_DIR")" 2>/dev/null || true

APP_SIZE=$(du -h "$APP_BACKUP_FILE" | cut -f1)
log "${GREEN}✓ Application backup completed: $APP_BACKUP_FILE ($APP_SIZE)${NC}"

# Step 3: Backup Configuration Files
log "3. Backing up configuration files"
CONFIG_BACKUP_FILE="$BACKUP_DIR/config_backup_${DATE}.tar.gz"

# Backup important config files
tar -czf "$CONFIG_BACKUP_FILE" \
    /etc/nginx/sites-available/zewedjobs \
    /etc/supervisor/conf.d/zewedjobs.conf \
    /etc/cron.d/zewedjobs \
    "$APP_DIR/telegram-bot/.env" \
    "$APP_DIR/admin-panel/config/.env" 2>/dev/null || true

log "${GREEN}✓ Configuration backup completed${NC}"

# Step 4: Create backup manifest
log "4. Creating backup manifest"
MANIFEST_FILE="$BACKUP_DIR/backup_manifest_${DATE}.txt"

cat > "$MANIFEST_FILE" << EOF
ZewedJobs Backup Manifest
========================
Backup Date: $(date)
Backup ID: $DATE
System: $(uname -a)

Files Backed Up:
1. Database: $(basename "$DB_BACKUP_FILE") ($DB_SIZE)
2. Application: $(basename "$APP_BACKUP_FILE") ($APP_SIZE)
3. Configuration: $(basename "$CONFIG_BACKUP_FILE")

Database Information:
- Database: $DB_NAME
- Tables: $(mysql -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE table_schema = '$DB_NAME'" 2>/dev/null || echo "Unknown")
- Total Size: $(mysql -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} -N -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) FROM information_schema.TABLES WHERE table_schema = '$DB_NAME'" 2>/dev/null || echo "Unknown") MB

Application Information:
- Directory: $APP_DIR
- Size: $(du -sh "$APP_DIR" 2>/dev/null | cut -f1 || echo "Unknown")

Verification:
$(sha256sum "$DB_BACKUP_FILE" "$APP_BACKUP_FILE" "$CONFIG_BACKUP_FILE" 2>/dev/null || echo "Checksum generation failed")

Restore Instructions:
1. Stop services: systemctl stop supervisor nginx
2. Restore database: zcat db_backup_${DATE}.sql.gz | mysql -u root -p zewedjobs_admin
3. Restore application: tar -xzf app_backup_${DATE}.tar.gz -C /var/www/
4. Restore config: tar -xzf config_backup_${DATE}.tar.gz -C /
5. Restart services: systemctl start supervisor nginx

Notes: This backup was created automatically by ZewedJobs backup system.
EOF

log "${GREEN}✓ Backup manifest created${NC}"

# Step 5: Verify backups
log "5. Verifying backups"

verify_backup() {
    local file="$1"
    local type="$2"
    
    if [ -f "$file" ] && [ $(stat -c%s "$file") -gt 1000 ]; then
        log "${GREEN}✓ $type backup verified${NC}"
        return 0
    else
        log "${RED}✗ $type backup verification failed${NC}"
        return 1
    fi
}

verify_backup "$DB_BACKUP_FILE" "Database"
verify_backup "$APP_BACKUP_FILE" "Application"
verify_backup "$CONFIG_BACKUP_FILE" "Configuration"

# Step 6: Clean up old backups
log "6. Cleaning up old backups (older than ${RETENTION_DAYS} days)"
find "$BACKUP_DIR" -name "*.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "*.txt" -mtime +$RETENTION_DAYS -delete

BACKUP_COUNT=$(find "$BACKUP_DIR" -name "*.gz" | wc -l)
log "Total backups retained: $BACKUP_COUNT"

# Step 7: Update backup log
log "7. Updating backup log"

cat >> "$BACKUP_DIR/backup_history.log" << EOF
$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | ID: $DATE | 
DB: $(basename "$DB_BACKUP_FILE") ($DB_SIZE) | 
APP: $(basename "$APP_BACKUP_FILE") ($APP_SIZE)
EOF

# Step 8: Send notification (optional)
if [ -f "$APP_DIR/scripts/send_notification.sh" ]; then
    log "8. Sending backup notification"
    "$APP_DIR/scripts/send_notification.sh" "Backup completed successfully: $DATE"
fi

echo ""
echo "🎉 Backup completed successfully!"
echo ""
echo "📁 Backup files created:"
echo "   • Database: $DB_BACKUP_FILE"
echo "   • Application: $APP_BACKUP_FILE"
echo "   • Configuration: $CONFIG_BACKUP_FILE"
echo "   • Manifest: $MANIFEST_FILE"
echo ""
echo "💾 Storage:"
echo "   • Backup directory: $BACKUP_DIR"
echo "   • Total backups: $BACKUP_COUNT"
echo "   • Retention: $RETENTION_DAYS days"
echo ""
echo "🔒 Backup verification: OK"
echo "🧹 Old backups cleaned: Yes"
echo ""
echo "📊 Next backup: $(date -d "+1 day" '+%Y-%m-%d %H:%M:%S')"
echo ""

# Calculate total backup size
TOTAL_SIZE=$(du -ch "$BACKUP_DIR"/*.gz 2>/dev/null | grep total | cut -f1)
log "Total backup storage used: ${TOTAL_SIZE:-0}"

exit 0
