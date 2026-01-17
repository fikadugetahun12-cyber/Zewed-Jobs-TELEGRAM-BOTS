#!/bin/bash

# ZewedJobs VPS Deployment Script
# Run this on a fresh Ubuntu/Debian server

set -e  # Exit on error

echo "🚀 ZewedJobs VPS Deployment Script"
echo "=================================="
echo ""
echo "This script will deploy ZewedJobs on a fresh VPS."
echo "It will install:"
echo "  • Python 3.11+"
echo "  • PHP 8.0+"
echo "  • MySQL 8.0+"
echo "  • Nginx"
echo "  • Redis (optional)"
echo "  • Git"
echo "  • ZewedJobs Application"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root. Use: sudo bash $0"
   exit 1
fi

# Configuration
DOMAIN="${1:-yourdomain.com}"
EMAIL="${2:-admin@$DOMAIN}"
DB_PASSWORD=$(openssl rand -base64 32)
SECRET_KEY=$(openssl rand -base64 64)

echo ""
echo "📝 Configuration:"
echo "  • Domain: $DOMAIN"
echo "  • Email: $EMAIL"
echo "  • Database password: (generated)"
echo "  • Secret key: (generated)"
echo ""

# Update system
echo "🔄 Updating system packages..."
apt update && apt upgrade -y

# Install required packages
echo "📦 Installing required packages..."
apt install -y \
    python3 python3-pip python3-venv python3-dev \
    php php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip \
    mysql-server mysql-client \
    nginx \
    git curl wget unzip \
    supervisor \
    certbot python3-certbot-nginx \
    redis-server \
    fail2ban \
    ufw

# Configure firewall
echo "🔥 Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw allow 5000  # For web dashboard
ufw enable

# Configure MySQL
echo "🗄️ Configuring MySQL..."
systemctl start mysql
systemctl enable mysql

# Secure MySQL installation
mysql_secure_installation <<EOF
y
$DB_PASSWORD
$DB_PASSWORD
y
y
y
y
EOF

# Create database and user
echo "🗃️ Creating ZewedJobs database..."
mysql -u root -p"$DB_PASSWORD" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS zewedjobs_admin CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'zewedjobs_user'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON zewedjobs_admin.* TO 'zewedjobs_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Create application directory
echo "📁 Setting up application directory..."
APP_DIR="/var/www/zewedjobs"
mkdir -p $APP_DIR
chown -R www-data:www-data $APP_DIR

# Clone or copy application
echo "📥 Getting ZewedJobs application..."
if [ -d ".git" ]; then
    # If running from git repo, copy files
    cp -r . $APP_DIR/
else
    # Clone from GitHub
    git clone https://github.com/yourusername/zewedjobs-complete.git $APP_DIR
fi

cd $APP_DIR

# Import database schema
echo "📊 Importing database schema..."
mysql -u root -p"$DB_PASSWORD" zewedjobs_admin < shared-database/schema.sql

# Setup Python environment
echo "🐍 Setting up Python environment..."
cd telegram-bot
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate
cd ..

# Configure environment files
echo "⚙️ Configuring environment..."
cat > telegram-bot/.env <<ENV_CONFIG
# Telegram Bot Configuration
BOT_TOKEN=your_telegram_bot_token_here
ADMIN_IDS=123456789

# Database Configuration
DB_HOST=localhost
DB_NAME=zewedjobs_admin
DB_USER=zewedjobs_user
DB_PASS=$DB_PASSWORD
DB_PORT=3306

# Web Dashboard
SECRET_KEY=$SECRET_KEY
ADMIN_USERNAME=admin
ADMIN_PASSWORD=admin123

# Production Settings
LOG_LEVEL=INFO
ENVIRONMENT=production
ENV_CONFIG

cat > admin-panel/config/.env <<PHP_ENV
# Database Configuration
DB_HOST=localhost
DB_NAME=zewedjobs_admin
DB_USER=zewedjobs_user
DB_PASS=$DB_PASSWORD

# Admin Credentials
ADMIN_USERNAME=admin
ADMIN_PASSWORD=admin123

# Application Settings
APP_NAME=ZewedJobs Admin
APP_ENV=production
APP_URL=https://$DOMAIN/admin
PHP_ENV

# Setup file permissions
echo "🔐 Setting file permissions..."
chown -R www-data:www-data $APP_DIR
chmod -R 755 $APP_DIR
chmod 644 admin-panel/config/.env telegram-bot/.env
chmod +x RUN_ME_FIRST.sh scripts/*.sh

# Configure Nginx
echo "🌐 Configuring Nginx..."
cat > /etc/nginx/sites-available/zewedjobs <<NGINX_CONFIG
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    root $APP_DIR;
    
    # Admin Panel (PHP)
    location /admin {
        alias $APP_DIR/admin-panel;
        index index.php;
        
        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/var/run/php/php-fpm.sock;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
        }
        
        location ~ /\.ht {
            deny all;
        }
    }
    
    # Web Dashboard (Python/Flask)
    location /dashboard {
        proxy_pass http://localhost:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Static files
    location /static {
        alias $APP_DIR/admin-panel/assets;
        expires 30d;
    }
    
    # API endpoints
    location /api {
        proxy_pass http://localhost:5000/api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    
    # SSL redirect
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL certificates (will be added by Certbot)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    ssl_prefer_server_ciphers off;
    
    root $APP_DIR;
    
    # Admin Panel
    location /admin {
        alias $APP_DIR/admin-panel;
        index index.php;
        
        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/var/run/php/php-fpm.sock;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
        }
        
        location ~ /\.ht {
            deny all;
        }
    }
    
    # Web Dashboard
    location /dashboard {
        proxy_pass http://localhost:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Static files
    location /static {
        alias $APP_DIR/admin-panel/assets;
        expires 30d;
    }
    
    # API endpoints
    location /api {
        proxy_pass http://localhost:5000/api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Logging
    access_log /var/log/nginx/zewedjobs_access.log;
    error_log /var/log/nginx/zewedjobs_error.log;
}
NGINX_CONFIG

# Enable site
ln -sf /etc/nginx/sites-available/zewedjobs /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

# Configure Supervisor for process management
echo "👨‍💼 Configuring Supervisor..."
cat > /etc/supervisor/conf.d/zewedjobs.conf <<SUPERVISOR_CONFIG
[program:zewedjobs-bot]
command=$APP_DIR/telegram-bot/venv/bin/python $APP_DIR/telegram-bot/bot.py
directory=$APP_DIR/telegram-bot
user=www-data
autostart=true
autorestart=true
stderr_logfile=/var/log/zewedjobs-bot.err.log
stdout_logfile=/var/log/zewedjobs-bot.out.log
environment=PYTHONPATH="$APP_DIR/telegram-bot"

[program:zewedjobs-dashboard]
command=$APP_DIR/telegram-bot/venv/bin/python $APP_DIR/telegram-bot/web_dashboard.py
directory=$APP_DIR/telegram-bot
user=www-data
autostart=true
autorestart=true
stderr_logfile=/var/log/zewedjobs-dashboard.err.log
stdout_logfile=/var/log/zewedjobs-dashboard.out.log
environment=PYTHONPATH="$APP_DIR/telegram-bot"
SUPERVISOR_CONFIG

# Start Supervisor
systemctl restart supervisor
supervisorctl reread
supervisorctl update

# Setup SSL with Certbot
echo "🔐 Setting up SSL certificate..."
if [ "$DOMAIN" != "yourdomain.com" ]; then
    certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --email $EMAIL
    systemctl restart nginx
else
    echo "⚠️ Using self-signed certificate for testing..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx-selfsigned.key \
        -out /etc/ssl/certs/nginx-selfsigned.crt \
        -subj "/C=ET/ST=Addis Ababa/L=Addis Ababa/O=ZewedJobs/CN=$DOMAIN"
fi

# Setup backup script
echo "💾 Setting up backup system..."
cat > $APP_DIR/scripts/backup.sh <<BACKUP_SCRIPT
#!/bin/bash
# ZewedJobs Backup Script

BACKUP_DIR="$APP_DIR/shared-database/backups"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\${BACKUP_DIR}/backup_\${DATE}.sql.gz"

mkdir -p \$BACKUP_DIR

# Backup database
mysqldump -u zewedjobs_user -p"$DB_PASSWORD" zewedjobs_admin | gzip > \$BACKUP_FILE

# Backup application files
tar -czf \${BACKUP_DIR}/app_backup_\${DATE}.tar.gz \
    --exclude="*/venv" \
    --exclude="*/node_modules" \
    --exclude="*.log" \
    $APP_DIR

# Keep only last 30 days of backups
find \$BACKUP_DIR -name "*.gz" -mtime +30 -delete

# Log backup
echo "\$(date): Backup completed - \${BACKUP_FILE}" >> $APP_DIR/backup.log
BACKUP_SCRIPT

chmod +x $APP_DIR/scripts/backup.sh

# Setup cron jobs
echo "⏰ Setting up cron jobs..."
(crontab -l 2>/dev/null; echo "0 2 * * * $APP_DIR/scripts/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * curl -s http://localhost:5000/health > /dev/null") | crontab -

# Setup monitoring
echo "📊 Setting up monitoring..."
cat > $APP_DIR/scripts/monitor.sh <<MONITOR_SCRIPT
#!/bin/bash
# Monitoring script

LOG_FILE="/var/log/zewedjobs_monitor.log"
ALERT_EMAIL="$EMAIL"

# Check if services are running
check_service() {
    service=\$1
    if ! systemctl is-active --quiet \$service; then
        echo "\$(date): Service \$service is down!" >> \$LOG_FILE
        systemctl restart \$service
        echo "\$(date): Restarted \$service" >> \$LOG_FILE
    fi
}

check_service mysql
check_service nginx
check_service php8.2-fpm
check_service supervisor

# Check disk space
DISK_USAGE=\$(df / | awk 'NR==2 {print \$5}' | sed 's/%//')
if [ \$DISK_USAGE -gt 90 ]; then
    echo "\$(date): Disk usage is high: \$DISK_USAGE%" >> \$LOG_FILE
fi

# Check memory usage
MEM_USAGE=\$(free | awk '/Mem:/ {print int(\$3/\$2 * 100)}')
if [ \$MEM_USAGE -gt 90 ]; then
    echo "\$(date): Memory usage is high: \$MEM_USAGE%" >> \$LOG_FILE
fi
MONITOR_SCRIPT

chmod +x $APP_DIR/scripts/monitor.sh
(crontab -l 2>/dev/null; echo "*/15 * * * * $APP_DIR/scripts/monitor.sh") | crontab -

# Setup log rotation
echo "📄 Setting up log rotation..."
cat > /etc/logrotate.d/zewedjobs <<LOGROTATE
/var/log/zewedjobs*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
    sharedscripts
    postrotate
        systemctl reload supervisor > /dev/null 2>&1 || true
    endscript
}

$APP_DIR/telegram-bot/bot.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
}
LOGROTATE

# Create admin user in database
echo "👤 Creating admin user..."
mysql -u root -p"$DB_PASSWORD" zewedjobs_admin <<MYSQL_ADMIN
UPDATE admin_users SET 
    password_hash = '\$2y\$10\$YourHashedPasswordHere' 
WHERE username = 'admin';
MYSQL_ADMIN

# Final steps
echo ""
echo "🎉 Deployment completed!"
echo ""
echo "📋 Next steps:"
echo "1. Edit configuration files:"
echo "   • $APP_DIR/telegram-bot/.env (add your BOT_TOKEN)"
echo "   • $APP_DIR/admin-panel/config/.env"
echo ""
echo "2. Start services:"
echo "   supervisorctl start zewedjobs-bot"
echo "   supervisorctl start zewedjobs-dashboard"
echo ""
echo "3. Access your applications:"
echo "   • Admin Panel: https://$DOMAIN/admin"
echo "   • Web Dashboard: https://$DOMAIN/dashboard"
echo ""
echo "4. Default credentials:"
echo "   • Username: admin"
echo "   • Password: admin123"
echo ""
echo "🔧 Management commands:"
echo "   • View logs: tail -f /var/log/zewedjobs*.log"
echo "   • Restart bot: supervisorctl restart zewedjobs-bot"
echo "   • Backup database: $APP_DIR/scripts/backup.sh"
echo ""
echo "📚 Documentation: $APP_DIR/docs/"
echo ""
echo "🚀 ZewedJobs is now deployed on your VPS!"
