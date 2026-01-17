#!/bin/bash

# ZewedJobs Health Check Script
# Checks all system components and services

echo "🔍 ZewedJobs System Health Check"
echo "=================================="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
APP_DIR="/var/www/zewedjobs"
DB_NAME="zewedjobs_admin"
LOG_FILE="/var/log/zewedjobs_health.log"
ERRORS=0

# Log function
log() {
    echo "$1"
    echo "[$(date)] $1" >> "$LOG_FILE"
}

# Check function
check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${RED}✗${NC} $1"
        ERRORS=$((ERRORS + 1))
    fi
}

# Start health check
echo "1. 🔄 System Information"
echo "----------------------"
log "System: $(uname -a)"
log "Uptime: $(uptime)"
log "Load: $(cat /proc/loadavg)"

echo ""
echo "2. 💾 Disk Usage"
echo "----------------"
df -h / | tail -1
check "Disk space OK"

echo ""
echo "3. 🧠 Memory Usage"
echo "-----------------"
free -h | awk '/^Mem:/ {print "Total: " $2, "Used: " $3, "Free: " $4, "Usage: " $3/$2*100 "%"}'
MEM_USAGE=$(free | awk '/Mem:/ {print int($3/$2 * 100)}')
if [ $MEM_USAGE -gt 90 ]; then
    echo -e "${RED}⚠ High memory usage: ${MEM_USAGE}%${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Memory usage OK${NC}"
fi

echo ""
echo "4. 🔥 Services Status"
echo "--------------------"

check_service() {
    service="$1"
    name="$2"
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓${NC} $name is running"
    else
        echo -e "${RED}✗${NC} $name is NOT running"
        ERRORS=$((ERRORS + 1))
    fi
}

check_service "mysql" "MySQL Database"
check_service "nginx" "Nginx Web Server"
check_service "php8.2-fpm" "PHP-FPM"
check_service "supervisor" "Supervisor"
check_service "redis-server" "Redis"

echo ""
echo "5. 🐍 Python Services"
echo "--------------------"

# Check if bot is running
if pgrep -f "bot.py" > /dev/null; then
    echo -e "${GREEN}✓ Telegram Bot is running${NC}"
else
    echo -e "${RED}✗ Telegram Bot is NOT running${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check if dashboard is running
if curl -s http://localhost:5000/ > /dev/null; then
    echo -e "${GREEN}✓ Web Dashboard is running${NC}"
else
    echo -e "${RED}✗ Web Dashboard is NOT running${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "6. 🗄️ Database Connectivity"
echo "--------------------------"

# Check MySQL connection
if mysql -u root -e "USE $DB_NAME; SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection OK${NC}"
    
    # Check database size
    DB_SIZE=$(mysql -u root -N -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) FROM information_schema.TABLES WHERE table_schema = '$DB_NAME'")
    log "Database size: ${DB_SIZE}MB"
    
    # Check table counts
    echo "Table Statistics:"
    mysql -u root $DB_NAME -e "
        SELECT 
            table_name AS 'Table',
            table_rows AS 'Rows',
            ROUND((data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
        FROM information_schema.TABLES 
        WHERE table_schema = '$DB_NAME'
        ORDER BY (data_length + index_length) DESC
        LIMIT 5;
    " 2>/dev/null || echo "Could not retrieve table stats"
    
else
    echo -e "${RED}✗ Database connection FAILED${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "7. 🌐 Web Server Status"
echo "----------------------"

# Check if admin panel is accessible
if curl -s -o /dev/null -w "%{http_code}" http://localhost/admin/ | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✓ Admin Panel is accessible${NC}"
else
    echo -e "${RED}✗ Admin Panel is NOT accessible${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check if dashboard is accessible
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/ | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✓ Web Dashboard is accessible${NC}"
else
    echo -e "${RED}✗ Web Dashboard is NOT accessible${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "8. 📊 Application Health"
echo "----------------------"

# Check log files
echo "Recent Errors (last 10 lines):"
find "$APP_DIR" -name "*.log" -type f -exec tail -10 {} \; 2>/dev/null | grep -i error | head -5 || echo "No recent errors found"

# Check backup directory
BACKUP_DIR="$APP_DIR/shared-database/backups"
if [ -d "$BACKUP_DIR" ]; then
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null | wc -l)
    if [ $BACKUP_COUNT -gt 0 ]; then
        LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.sql.gz | head -1)
        BACKUP_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 86400 ))
        
        if [ $BACKUP_AGE -lt 2 ]; then
            echo -e "${GREEN}✓ Recent backup exists (${BACKUP_AGE} days old)${NC}"
        else
            echo -e "${YELLOW}⚠ Last backup is ${BACKUP_AGE} days old${NC}"
        fi
    else
        echo -e "${RED}✗ No backups found${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${RED}✗ Backup directory not found${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check file permissions
echo ""
echo "9. 🔐 File Permissions"
echo "----------------------"

check_permission() {
    file="$1"
    if [ -f "$file" ]; then
        perms=$(stat -c "%a %U:%G" "$file")
        if [[ "$perms" == "644 www-data:www-data" ]] || [[ "$perms" == "755 www-data:www-data" ]]; then
            echo -e "${GREEN}✓ $file permissions OK ($perms)${NC}"
        else
            echo -e "${RED}✗ $file incorrect permissions ($perms)${NC}"
            ERRORS=$((ERRORS + 1))
        fi
    fi
}

check_permission "$APP_DIR/telegram-bot/.env"
check_permission "$APP_DIR/admin-panel/config/.env"
check_permission "$APP_DIR/telegram-bot/bot.py"
check_permission "$APP_DIR/admin-panel/index.php"

echo ""
echo "10. 🔔 Cron Jobs"
echo "----------------"

# Check if cron jobs are set up
CRON_COUNT=$(crontab -l 2>/dev/null | grep -c "zewedjobs\|backup\|certbot")
if [ $CRON_COUNT -ge 2 ]; then
    echo -e "${GREEN}✓ Cron jobs are configured (${CRON_COUNT} found)${NC}"
else
    echo -e "${RED}✗ Missing cron jobs${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "📈 System Statistics"
echo "-------------------"

# Get user count
USER_COUNT=$(mysql -u root -N -e "SELECT COUNT(*) FROM users" $DB_NAME 2>/dev/null || echo "0")
echo "• Total Users: $USER_COUNT"

# Get job count
JOB_COUNT=$(mysql -u root -N -e "SELECT COUNT(*) FROM jobs WHERE status = 'active'" $DB_NAME 2>/dev/null || echo "0")
echo "• Active Jobs: $JOB_COUNT"

# Get application count
APP_COUNT=$(mysql -u root -N -e "SELECT COUNT(*) FROM applications WHERE DATE(applied_at) = CURDATE()" $DB_NAME 2>/dev/null || echo "0")
echo "• Today's Applications: $APP_COUNT"

# Get bot messages today
MSG_COUNT=$(mysql -u root -N -e "SELECT COUNT(*) FROM messages WHERE DATE(timestamp) = CURDATE()" $DB_NAME 2>/dev/null || echo "0")
echo "• Bot Messages Today: $MSG_COUNT"

echo ""
echo "📋 Summary"
echo "----------"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All systems are healthy!${NC}"
    echo "No issues detected."
    exit 0
elif [ $ERRORS -le 3 ]; then
    echo -e "${YELLOW}⚠ System has ${ERRORS} warning(s)${NC}"
    echo "Some minor issues detected. Check logs for details."
    exit 1
else
    echo -e "${RED}❌ System has ${ERRORS} critical error(s)${NC}"
    echo "Immediate attention required!"
    exit 2
fi
