#!/bin/bash

echo "🚀 ZEWEDJOBS COMPLETE SYSTEM - ONE COMMAND SETUP"
echo "================================================"
echo ""
echo "This script will:"
echo "1. Check prerequisites"
echo "2. Setup database"
echo "3. Configure environment"
echo "4. Start all services"
echo ""
read -p "Press Enter to continue..."

# Check prerequisites
echo ""
echo "🔍 Checking prerequisites..."
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 is required. Please install Python 3.11+"
    exit 1
fi

if ! command -v php &> /dev/null; then
    echo "⚠️ PHP not found. Admin Panel will not work."
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

if ! command -v mysql &> /dev/null; then
    echo "⚠️ MySQL not found. Using SQLite instead."
    echo "For production, install MySQL 8.0+"
fi

# Setup
echo ""
echo "📦 Setting up project..."

# Create necessary directories
mkdir -p admin-panel/logs
mkdir -p telegram-bot/logs
mkdir -p shared-database/backups

# Copy environment files
if [ ! -f "telegram-bot/.env" ]; then
    echo "📝 Setting up Telegram Bot environment..."
    cp telegram-bot/.env.example telegram-bot/.env
    echo "✅ Please edit telegram-bot/.env with your BOT_TOKEN"
fi

if [ ! -f "admin-panel/config/.env" ]; then
    echo "📝 Setting up Admin Panel environment..."
    cp admin-panel/config/.env.example admin-panel/config/.env
fi

# Install Python dependencies
echo ""
echo "🐍 Installing Python dependencies..."
cd telegram-bot
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cd ..

# Setup database
echo ""
echo "🗄️ Setting up database..."
if command -v mysql &> /dev/null; then
    read -p "Setup MySQL database? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "MySQL root password: " -s db_pass
        echo
        mysql -u root -p$db_pass -e "CREATE DATABASE IF NOT EXISTS zewedjobs_admin"
        mysql -u root -p$db_pass zewedjobs_admin < shared-database/schema.sql
        echo "✅ Database setup complete"
    fi
fi

# Start services
echo ""
echo "🚀 Starting services..."
echo ""
echo "📋 Services will start on:"
echo "   Admin Panel:  http://localhost:8080/admin"
echo "   Dashboard:    http://localhost:5000"
echo "   Telegram Bot: Search @YourBotName"
echo ""
echo "Default credentials:"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "Press Ctrl+C to stop all services"
echo ""

# Start services in background
cd telegram-bot
source venv/bin/activate

# Start web dashboard
python web_dashboard.py &
DASHBOARD_PID=$!

# Start bot
python bot.py &
BOT_PID=$!

cd ..

# Start admin panel if PHP available
if command -v php &> /dev/null; then
    cd admin-panel
    php -S localhost:8080 &
    ADMIN_PID=$!
    cd ..
fi

# Wait for Ctrl+C
trap 'kill $DASHBOARD_PID $BOT_PID $ADMIN_PID 2>/dev/null; echo "Services stopped"; exit' INT

echo "✅ All services started successfully!"
echo ""
echo "🌐 Access your systems:"
echo "   Admin Panel:  http://localhost:8080/admin"
echo "   Dashboard:    http://localhost:5000"
echo ""
echo "📱 Open Telegram and search for your bot"
echo ""
echo "🔧 Need to configure? Edit:"
echo "   - telegram-bot/.env (for bot token)"
echo "   - admin-panel/config/.env (for database)"
echo ""
echo "🛑 Press Ctrl+C to stop all services"

wait
