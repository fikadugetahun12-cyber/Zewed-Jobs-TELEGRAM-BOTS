#!/usr/bin/env python3
"""
ZewedJobs Telegram Bot
A complete job portal bot for the Ethiopian job market
"""

import os
import logging
from typing import Optional, Dict, List
from datetime import datetime, timedelta
from dotenv import load_dotenv

# Telegram Bot API
from telegram import (
    Update, InlineKeyboardButton, InlineKeyboardMarkup,
    ReplyKeyboardMarkup, KeyboardButton, WebAppInfo
)
from telegram.ext import (
    Application, CommandHandler, MessageHandler, 
    CallbackQueryHandler, ContextTypes, filters
)

# Database
import mysql.connector
from mysql.connector import Error

# Load environment variables
load_dotenv()

# Configuration
BOT_TOKEN = os.getenv('BOT_TOKEN')
ADMIN_IDS = list(map(int, os.getenv('ADMIN_IDS', '').split(','))) if os.getenv('ADMIN_IDS') else []
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'database': os.getenv('DB_NAME', 'zewedjobs_admin'),
    'user': os.getenv('DB_USER', 'root'),
    'password': os.getenv('DB_PASS', ''),
    'port': os.getenv('DB_PORT', '3306')
}

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Database connection
class Database:
    def __init__(self):
        self.connection = None
        self.connect()
    
    def connect(self):
        try:
            self.connection = mysql.connector.connect(**DB_CONFIG)
            logger.info("Database connection established")
        except Error as e:
            logger.error(f"Database connection failed: {e}")
            self.connection = None
    
    def get_connection(self):
        if self.connection and self.connection.is_connected():
            return self.connection
        self.connect()
        return self.connection
    
    def execute_query(self, query: str, params: tuple = None, fetch_one: bool = False):
        connection = self.get_connection()
        if not connection:
            return None
        
        cursor = connection.cursor(dictionary=True)
        try:
            cursor.execute(query, params or ())
            if fetch_one:
                result = cursor.fetchone()
            else:
                result = cursor.fetchall()
            connection.commit()
            return result
        except Error as e:
            logger.error(f"Query failed: {e}")
            connection.rollback()
            return None
        finally:
            cursor.close()
    
    def execute_update(self, query: str, params: tuple = None):
        connection = self.get_connection()
        if not connection:
            return False
        
        cursor = connection.cursor()
        try:
            cursor.execute(query, params or ())
            connection.commit()
            return True
        except Error as e:
            logger.error(f"Update failed: {e}")
            connection.rollback()
            return False
        finally:
            cursor.close()

db = Database()

# Helper functions
def get_user(telegram_id: int):
    """Get user from database by Telegram ID"""
    query = "SELECT * FROM users WHERE telegram_id = %s"
    return db.execute_query(query, (telegram_id,), fetch_one=True)

def create_user(telegram_id: int, username: str = None, full_name: str = None):
    """Create new user in database"""
    query = """
    INSERT INTO users (telegram_id, username, full_name, user_type, status, created_at)
    VALUES (%s, %s, %s, 'job_seeker', 'active', NOW())
    ON DUPLICATE KEY UPDATE last_seen = NOW()
    """
    return db.execute_update(query, (telegram_id, username, full_name))

def get_jobs(limit: int = 10, category: str = None, location: str = None):
    """Get jobs from database with optional filters"""
    query = """
    SELECT j.*, c.name as company_name, c.logo as company_logo
    FROM jobs j
    LEFT JOIN companies c ON j.company_id = c.id
    WHERE j.status = 'active' AND j.deadline >= CURDATE()
    """
    params = []
    
    if category:
        query += " AND j.category = %s"
        params.append(category)
    
    if location:
        query += " AND j.location LIKE %s"
        params.append(f"%{location}%")
    
    query += " ORDER BY j.created_at DESC LIMIT %s"
    params.append(limit)
    
    return db.execute_query(query, tuple(params))

def get_job_details(job_id: int):
    """Get detailed job information"""
    query = """
    SELECT j.*, c.name as company_name, c.description as company_description,
           c.email as company_email, c.website as company_website
    FROM jobs j
    LEFT JOIN companies c ON j.company_id = c.id
    WHERE j.id = %s
    """
    return db.execute_query(query, (job_id,), fetch_one=True)

# Bot handlers
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send welcome message when /start is issued"""
    user = update.effective_user
    create_user(user.id, user.username, user.full_name)
    
    welcome_text = f"""
    👋 *Welcome to ZewedJobs, {user.first_name}!*

    🇪🇹 *Your Gateway to Ethiopian Job Opportunities*

    📋 *Available Commands:*
    /jobs - Browse latest job openings
    /search - Search jobs by keywords
    /profile - View and update your profile
    /applications - Track your applications
    /subscribe - Get job alerts
    /help - Show help message
    /admin - Admin panel (for admins only)

    💼 *For Employers:*
    /post_job - Post a new job opening
    /my_jobs - Manage your job postings

    📊 *Quick Stats:*
    • 500+ Active Jobs
    • 200+ Companies
    • 10,000+ Job Seekers
    • 95% Success Rate

    🚀 *Start your journey now!*
    """
    
    keyboard = [
        [InlineKeyboardButton("🔍 Browse Jobs", callback_data="browse_jobs")],
        [InlineKeyboardButton("📝 Create Profile", callback_data="create_profile")],
        [InlineKeyboardButton("💼 For Employers", callback_data="employer_info")],
        [InlineKeyboardButton("📊 View Statistics", callback_data="statistics")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        welcome_text,
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )

async def jobs_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show latest job listings"""
    jobs = get_jobs(limit=5)
    
    if not jobs:
        await update.message.reply_text("📭 No jobs available at the moment. Check back later!")
        return
    
    for job in jobs:
        job_text = f"""
        *{job['title']}*
        
        🏢 *Company:* {job['company_name']}
        📍 *Location:* {job['location']}
        💰 *Salary:* ETB {job['salary_min']:,} - {job['salary_max']:,}
        📅 *Deadline:* {job['deadline'].strftime('%b %d, %Y')}
        
        *{job['description'][:150]}...*
        
        🆔 Job ID: #{job['id']}
        """
        
        keyboard = [
            [
                InlineKeyboardButton("📄 View Details", callback_data=f"view_job_{job['id']}"),
                InlineKeyboardButton("📝 Apply Now", callback_data=f"apply_job_{job['id']}")
            ]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(
            job_text,
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )

async def search_jobs(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Search jobs by keyword"""
    if not context.args:
        await update.message.reply_text(
            "🔍 *Search Jobs*\n\n"
            "Please specify search keywords:\n"
            "Example: `/search software engineer addis ababa`\n"
            "Example: `/search marketing remote`",
            parse_mode='Markdown'
        )
        return
    
    search_query = ' '.join(context.args)
    
    # Search in database
    query = """
    SELECT j.*, c.name as company_name
    FROM jobs j
    LEFT JOIN companies c ON j.company_id = c.id
    WHERE j.status = 'active' 
      AND j.deadline >= CURDATE()
      AND (j.title LIKE %s OR j.description LIKE %s OR j.location LIKE %s)
    ORDER BY j.created_at DESC
    LIMIT 10
    """
    
    search_pattern = f"%{search_query}%"
    jobs = db.execute_query(query, (search_pattern, search_pattern, search_pattern))
    
    if not jobs:
        await update.message.reply_text(
            f"❌ No jobs found for: *{search_query}*\n\n"
            "Try different keywords or check back later.",
            parse_mode='Markdown'
        )
        return
    
    await update.message.reply_text(f"🔍 Found *{len(jobs)}* jobs for: *{search_query}*", parse_mode='Markdown')
    
    for job in jobs:
        job_text = f"""
        *{job['title']}* - {job['company_name']}
        📍 {job['location']} • 💰 ETB {job['salary_min']:,}
        """
        
        keyboard = [[
            InlineKeyboardButton("View Details", callback_data=f"view_job_{job['id']}"),
            InlineKeyboardButton("Apply", callback_data=f"apply_job_{job['id']}")
        ]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(job_text, reply_markup=reply_markup, parse_mode='Markdown')

async def view_profile(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show user profile"""
    user = get_user(update.effective_user.id)
    
    if not user:
        await update.message.reply_text(
            "👤 *Profile Not Found*\n\n"
            "Please use /start to create your profile first.",
            parse_mode='Markdown'
        )
        return
    
    profile_text = f"""
    👤 *Your Profile*
    
    *Name:* {user['full_name'] or 'Not set'}
    *Username:* @{user['username'] or 'Not set'}
    *Email:* {user['email'] or 'Not set'}
    *Phone:* {user['phone'] or 'Not set'}
    *User Type:* {user['user_type'].replace('_', ' ').title()}
    *Status:* {user['status'].title()}
    
    *Statistics:*
    • Applications: {user.get('applications_count', 0)}
    • Profile Completion: {calculate_profile_completion(user)}%
    • Member Since: {user['created_at'].strftime('%b %d, %Y')}
    """
    
    keyboard = [
        [
            InlineKeyboardButton("✏️ Edit Profile", callback_data="edit_profile"),
            InlineKeyboardButton("📄 My Applications", callback_data="my_applications")
        ],
        [
            InlineKeyboardButton("💼 Switch to Employer", callback_data="switch_employer"),
            InlineKeyboardButton("🔔 Notification Settings", callback_data="notification_settings")
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(profile_text, reply_markup=reply_markup, parse_mode='Markdown')

async def admin_panel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Admin panel for managing the system"""
    user_id = update.effective_user.id
    
    if user_id not in ADMIN_IDS:
        await update.message.reply_text("❌ Access denied. Admin only.")
        return
    
    # Get admin statistics
    stats_query = """
    SELECT 
        (SELECT COUNT(*) FROM users) as total_users,
        (SELECT COUNT(*) FROM jobs WHERE status = 'active') as active_jobs,
        (SELECT COUNT(*) FROM companies WHERE status = 'active') as active_companies,
        (SELECT COUNT(*) FROM applications WHERE DATE(created_at) = CURDATE()) as today_applications
    """
    stats = db.execute_query(stats_query, fetch_one=True)
    
    admin_text = f"""
    👑 *Admin Panel*
    
    📊 *Statistics:*
    • Total Users: {stats['total_users']:,}
    • Active Jobs: {stats['active_jobs']:,}
    • Active Companies: {stats['active_companies']:,}
    • Today's Applications: {stats['today_applications']:,}
    
    ⚙️ *Admin Commands:*
    /admin_stats - Detailed statistics
    /admin_users - User management
    /admin_jobs - Job management
    /admin_companies - Company management
    /admin_broadcast - Send broadcast message
    /admin_backup - Create system backup
    """
    
    keyboard = [
        [
            InlineKeyboardButton("📊 Dashboard", web_app=WebAppInfo(url="https://your-admin-url.com")),
            InlineKeyboardButton("👥 Users", callback_data="admin_users")
        ],
        [
            InlineKeyboardButton("💼 Jobs", callback_data="admin_jobs"),
            InlineKeyboardButton("🏢 Companies", callback_data="admin_companies")
        ],
        [
            InlineKeyboardButton("📢 Broadcast", callback_data="admin_broadcast"),
            InlineKeyboardButton("💾 Backup", callback_data="admin_backup")
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(admin_text, reply_markup=reply_markup, parse_mode='Markdown')

async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle button callbacks"""
    query = update.callback_query
    await query.answer()
    
    data = query.data
    
    if data == "browse_jobs":
        await jobs_command(update, context)
    elif data.startswith("view_job_"):
        job_id = int(data.split("_")[-1])
        await show_job_details(update, context, job_id)
    elif data == "create_profile":
        await create_profile(update, context)
    elif data == "statistics":
        await show_statistics(update, context)
    elif data.startswith("admin_"):
        await handle_admin_action(update, context, data)
    
    await query.edit_message_reply_markup(reply_markup=None)

async def show_job_details(update: Update, context: ContextTypes.DEFAULT_TYPE, job_id: int):
    """Show detailed job information"""
    job = get_job_details(job_id)
    
    if not job:
        await update.callback_query.message.reply_text("❌ Job not found.")
        return
    
    job_text = f"""
    🎯 *Job Details*
    
    *{job['title']}*
    
    🏢 *Company:* {job['company_name']}
    📍 *Location:* {job['location']}
    💰 *Salary:* ETB {job['salary_min']:,} - {job['salary_max']:,}
    📅 *Deadline:* {job['deadline'].strftime('%B %d, %Y')}
    🔧 *Job Type:* {job['job_type'].replace('_', ' ').title()}
    🎓 *Experience:* {job['experience_level'].replace('_', ' ').title()}
    
    📝 *Description:*
    {job['description']}
    
    📋 *Requirements:*
    {job['requirements'] or 'Not specified'}
    
    🏢 *About Company:*
    {job['company_description'][:200] if job['company_description'] else 'No company description available.'}
    
    📧 *Contact:* {job['company_email'] or 'N/A'}
    🌐 *Website:* {job['company_website'] or 'N/A'}
    
    🆔 Job ID: #{job['id']}
    """
    
    keyboard = [
        [
            InlineKeyboardButton("📝 Apply Now", callback_data=f"apply_job_{job_id}"),
            InlineKeyboardButton("💾 Save Job", callback_data=f"save_job_{job_id}")
        ],
        [
            InlineKeyboardButton("🏢 View Company", callback_data=f"view_company_{job['company_id']}"),
            InlineKeyboardButton("🔍 Similar Jobs", callback_data=f"similar_jobs_{job_id}")
        ],
        [InlineKeyboardButton("⬅️ Back to Jobs", callback_data="browse_jobs")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.callback_query.message.reply_text(job_text, reply_markup=reply_markup, parse_mode='Markdown')

async def create_profile(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Create or update user profile"""
    user_id = update.effective_user.id
    
    profile_text = """
    👤 *Create Your Profile*
    
    To help you find the best job matches, please provide the following information:
    
    1. *Full Name* (required)
    2. *Email Address* (required)
    3. *Phone Number* (required)
    4. *Profession/Field*
    5. *Years of Experience*
    6. *Highest Education Level*
    7. *Skills (comma separated)*
    8. *Preferred Job Location*
    9. *Expected Salary Range*
    
    Please reply with your information in this format:
    
    ```
    Name: Your Full Name
    Email: your.email@example.com
    Phone: +251 91 234 5678
    Profession: Software Engineer
    Experience: 3 years
    Education: BSc in Computer Science
    Skills: Python, Django, React, PostgreSQL
    Location: Addis Ababa
    Salary: 15000-25000 ETB
    ```
    """
    
    await update.callback_query.message.reply_text(profile_text, parse_mode='Markdown')

async def show_statistics(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show system statistics"""
    stats_query = """
    SELECT 
        (SELECT COUNT(*) FROM users WHERE user_type = 'job_seeker') as job_seekers,
        (SELECT COUNT(*) FROM users WHERE user_type = 'employer') as employers,
        (SELECT COUNT(*) FROM jobs WHERE status = 'active') as active_jobs,
        (SELECT COUNT(*) FROM applications WHERE status = 'pending') as pending_applications,
        (SELECT COUNT(*) FROM applications WHERE status = 'accepted') as accepted_applications,
        (SELECT COUNT(DISTINCT location) FROM jobs WHERE status = 'active') as locations
    """
    stats = db.execute_query(stats_query, fetch_one=True)
    
    stats_text = f"""
    📊 *ZewedJobs Statistics*
    
    👥 *Users:*
    • Job Seekers: {stats['job_seekers']:,}
    • Employers: {stats['employers']:,}
    
    💼 *Jobs:*
    • Active Jobs: {stats['active_jobs']:,}
    • Locations: {stats['locations']:,} cities
    
    📝 *Applications:*
    • Pending: {stats['pending_applications']:,}
    • Accepted: {stats['accepted_applications']:,}
    
    📈 *Success Rate:* 95%
    🚀 *Average Response Time:* 24-48 hours
    
    *Top Job Categories:*
    1. IT & Technology (35%)
    2. Engineering (20%)
    3. Sales & Marketing (15%)
    4. Finance (12%)
    5. Healthcare (10%)
    6. Others (8%)
    """
    
    await update.callback_query.message.reply_text(stats_text, parse_mode='Markdown')

async def handle_admin_action(update: Update, context: ContextTypes.DEFAULT_TYPE, action: str):
    """Handle admin actions"""
    user_id = update.effective_user.id
    
    if user_id not in ADMIN_IDS:
        await update.callback_query.message.reply_text("❌ Access denied.")
        return
    
    if action == "admin_users":
        await admin_manage_users(update, context)
    elif action == "admin_jobs":
        await admin_manage_jobs(update, context)
    elif action == "admin_companies":
        await admin_manage_companies(update, context)

async def admin_manage_users(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Admin: Manage users"""
    users_query = """
    SELECT id, full_name, username, user_type, status, created_at
    FROM users
    ORDER BY created_at DESC
    LIMIT 10
    """
    users = db.execute_query(users_query)
    
    if not users:
        await update.callback_query.message.reply_text("📭 No users found.")
        return
    
    users_text = "👥 *Recent Users*\n\n"
    for user in users:
        users_text += f"""
        👤 *{user['full_name'] or 'Anonymous'}*
        Username: @{user['username'] or 'N/A'}
        Type: {user['user_type'].replace('_', ' ').title()}
        Status: {user['status'].title()}
        Joined: {user['created_at'].strftime('%Y-%m-%d')}
        ──────────────────────
        """
    
    keyboard = [
        [InlineKeyboardButton("📊 All Users", callback_data="admin_all_users")],
        [InlineKeyboardButton("⏫ Promote to Admin", callback_data="admin_promote")],
        [InlineKeyboardButton("⏬ Demote Admin", callback_data="admin_demote")],
        [InlineKeyboardButton("❌ Ban User", callback_data="admin_ban")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.callback_query.message.reply_text(users_text, reply_markup=reply_markup, parse_mode='Markdown')

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send help message"""
    help_text = """
    📚 *ZewedJobs Bot Help*
    
    *For Job Seekers:*
    /start - Start the bot and see welcome message
    /jobs - Browse latest job openings
    /search <keywords> - Search jobs by keyword/location
    /profile - View and update your profile
    /applications - Track your job applications
    /subscribe - Subscribe to job alerts
    /saved - View saved jobs
    
    *For Employers:*
    /post_job - Post a new job opening
    /my_jobs - View and manage your job postings
    /applicants - View job applicants
    
    *Admin Commands:*
    /admin - Access admin panel
    /stats - View system statistics
    /broadcast - Send announcement to all users
    
    *Support:*
    /help - Show this help message
    /contact - Contact support team
    /feedback - Send feedback
    
    *Tips:*
    • Complete your profile for better job matches
    • Use specific keywords when searching
    • Apply early for better chances
    • Save jobs you're interested in
    
    📧 *Contact Support:* support@zewedjobs.com
    🌐 *Website:* https://zewedjobs.com
    """
    
    await update.message.reply_text(help_text, parse_mode='Markdown')

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Log errors"""
    logger.error(f"Update {update} caused error {context.error}")
    
    # Notify admins about critical errors
    error_message = f"""
    ⚠️ *Bot Error*
    
    *Error:* {context.error}
    *User:* {update.effective_user.id if update.effective_user else 'N/A'}
    *Chat:* {update.effective_chat.id if update.effective_chat else 'N/A'}
    *Time:* {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
    """
    
    for admin_id in ADMIN_IDS:
        try:
            await context.bot.send_message(admin_id, error_message, parse_mode='Markdown')
        except:
            pass

def calculate_profile_completion(user: dict) -> int:
    """Calculate user profile completion percentage"""
    fields = ['full_name', 'email', 'phone', 'profession', 'experience', 'education', 'skills']
    completed = sum(1 for field in fields if user.get(field))
    return int((completed / len(fields)) * 100)

# Scheduled tasks
async def send_daily_alerts(context: ContextTypes.DEFAULT_TYPE):
    """Send daily job alerts to subscribed users"""
    query = """
    SELECT u.telegram_id, u.preferences
    FROM users u
    WHERE u.notifications_enabled = 1
      AND u.status = 'active'
    """
    users = db.execute_query(query)
    
    if not users:
        return
    
    # Get new jobs from last 24 hours
    jobs_query = """
    SELECT j.*, c.name as company_name
    FROM jobs j
    LEFT JOIN companies c ON j.company_id = c.id
    WHERE j.status = 'active'
      AND j.created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)
    LIMIT 5
    """
    jobs = db.execute_query(jobs_query)
    
    if not jobs:
        return
    
    alert_text = f"""
    🔔 *Daily Job Alerts*
    
    Found *{len(jobs)}* new jobs matching your preferences:
    
    """
    
    for job in jobs:
        alert_text += f"""
        • *{job['title']}* - {job['company_name']}
          📍 {job['location']} • 💰 ETB {job['salary_min']:,}
          Apply: /apply_{job['id']}
        
        """
    
    alert_text += "\n📊 View all jobs: /jobs\n"
    alert_text += "⚙️ Update preferences: /profile"
    
    for user in users:
        try:
            await context.bot.send_message(
                user['telegram_id'],
                alert_text,
                parse_mode='Markdown'
            )
        except Exception as e:
            logger.error(f"Failed to send alert to {user['telegram_id']}: {e}")

async def cleanup_old_data(context: ContextTypes.DEFAULT_TYPE):
    """Clean up old data and logs"""
    # Delete jobs older than 90 days
    cleanup_query = """
    DELETE FROM jobs 
    WHERE status = 'expired' 
      AND updated_at < DATE_SUB(NOW(), INTERVAL 90 DAY)
    """
    db.execute_update(cleanup_query)
    
    logger.info("Cleanup completed")

# Main function
def main():
    """Start the bot"""
    if not BOT_TOKEN:
        logger.error("BOT_TOKEN not found in environment variables")
        return
    
    # Create application
    application = Application.builder().token(BOT_TOKEN).build()
    
    # Add command handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("jobs", jobs_command))
    application.add_handler(CommandHandler("search", search_jobs))
    application.add_handler(CommandHandler("profile", view_profile))
    application.add_handler(CommandHandler("admin", admin_panel))
    application.add_handler(CommandHandler("help", help_command))
    
    # Add callback query handler
    application.add_handler(CallbackQueryHandler(button_handler))
    
    # Add error handler
    application.add_error_handler(error_handler)
    
    # Add job queue for scheduled tasks
    job_queue = application.job_queue
    
    # Schedule daily alerts at 9 AM
    job_queue.run_daily(send_daily_alerts, time=datetime.strptime("09:00", "%H:%M").time())
    
    # Schedule weekly cleanup on Sunday at 2 AM
    job_queue.run_daily(cleanup_old_data, time=datetime.strptime("02:00", "%H:%M").time(), days=(6,))
    
    # Start the bot
    logger.info("Starting bot...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
