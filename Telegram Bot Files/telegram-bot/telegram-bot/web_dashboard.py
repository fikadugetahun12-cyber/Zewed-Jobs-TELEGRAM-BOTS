#!/usr/bin/env python3
"""
ZewedJobs Web Dashboard
Flask web interface for monitoring bot statistics
"""

from flask import Flask, render_template, jsonify, request, session, redirect, url_for
from flask_cors import CORS
import os
from dotenv import load_dotenv
import mysql.connector
from mysql.connector import Error
from datetime import datetime, timedelta
import logging

# Load environment variables
load_dotenv()

# Flask app
app = Flask(__name__)
app.secret_key = os.getenv('SECRET_KEY', 'zewedjobs-secret-key-2024')
CORS(app)

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'database': os.getenv('DB_NAME', 'zewedjobs_admin'),
    'user': os.getenv('DB_USER', 'root'),
    'password': os.getenv('DB_PASS', ''),
    'port': os.getenv('DB_PORT', '3306')
}

# Admin credentials (in production, use proper authentication)
ADMIN_USERNAME = os.getenv('ADMIN_USERNAME', 'admin')
ADMIN_PASSWORD = os.getenv('ADMIN_PASSWORD', 'admin123')

def get_db_connection():
    """Create database connection"""
    try:
        connection = mysql.connector.connect(**DB_CONFIG)
        return connection
    except Error as e:
        print(f"Database connection failed: {e}")
        return None

# Routes
@app.route('/')
def index():
    """Home page - redirect to login if not authenticated"""
    if not session.get('logged_in'):
        return redirect(url_for('login'))
    return redirect(url_for('dashboard'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login page"""
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
            session['logged_in'] = True
            session['username'] = username
            return redirect(url_for('dashboard'))
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    """Logout user"""
    session.clear()
    return redirect(url_for('login'))

@app.route('/dashboard')
def dashboard():
    """Main dashboard"""
    if not session.get('logged_in'):
        return redirect(url_for('login'))
    
    connection = get_db_connection()
    if not connection:
        return "Database connection failed", 500
    
    cursor = connection.cursor(dictionary=True)
    
    # Get statistics
    stats_query = """
    SELECT 
        (SELECT COUNT(*) FROM users) as total_users,
        (SELECT COUNT(*) FROM users WHERE DATE(created_at) = CURDATE()) as new_users_today,
        (SELECT COUNT(*) FROM jobs WHERE status = 'active') as active_jobs,
        (SELECT COUNT(*) FROM applications WHERE DATE(created_at) = CURDATE()) as today_applications,
        (SELECT COUNT(*) FROM messages WHERE DATE(timestamp) = CURDATE()) as messages_today,
        (SELECT COUNT(DISTINCT user_id) FROM messages WHERE DATE(timestamp) = CURDATE()) as active_users_today
    """
    cursor.execute(stats_query)
    stats = cursor.fetchone()
    
    # Get recent users
    users_query = """
    SELECT id, telegram_id, username, full_name, user_type, status, created_at
    FROM users
    ORDER BY created_at DESC
    LIMIT 10
    """
    cursor.execute(users_query)
    recent_users = cursor.fetchall()
    
    # Get recent jobs
    jobs_query = """
    SELECT j.id, j.title, c.name as company_name, j.location, j.created_at, j.status
    FROM jobs j
    LEFT JOIN companies c ON j.company_id = c.id
    ORDER BY j.created_at DESC
    LIMIT 10
    """
    cursor.execute(jobs_query)
    recent_jobs = cursor.fetchall()
    
    # Get user growth data (last 7 days)
    growth_query = """
    SELECT DATE(created_at) as date, COUNT(*) as count
    FROM users
    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    GROUP BY DATE(created_at)
    ORDER BY date
    """
    cursor.execute(growth_query)
    user_growth = cursor.fetchall()
    
    cursor.close()
    connection.close()
    
    return render_template(
        'dashboard.html',
        stats=stats,
        recent_users=recent_users,
        recent_jobs=recent_jobs,
        user_growth=user_growth,
        username=session.get('username')
    )

@app.route('/api/stats')
def api_stats():
    """API endpoint for statistics"""
    if not session.get('logged_in'):
        return jsonify({'error': 'Unauthorized'}), 401
    
    connection = get_db_connection()
    if not connection:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = connection.cursor(dictionary=True)
    
    # Overall statistics
    stats_query = """
    SELECT 
        (SELECT COUNT(*) FROM users) as total_users,
        (SELECT COUNT(*) FROM users WHERE user_type = 'job_seeker') as job_seekers,
        (SELECT COUNT(*) FROM users WHERE user_type = 'employer') as employers,
        (SELECT COUNT(*) FROM jobs) as total_jobs,
        (SELECT COUNT(*) FROM jobs WHERE status = 'active') as active_jobs,
        (SELECT COUNT(*) FROM companies) as total_companies,
        (SELECT COUNT(*) FROM applications) as total_applications,
        (SELECT COUNT(*) FROM messages) as total_messages
    """
    cursor.execute(stats_query)
    stats = cursor.fetchone()
    
    # Daily statistics
    daily_query = """
    SELECT 
        DATE(created_at) as date,
        COUNT(*) as new_users,
        (SELECT COUNT(*) FROM jobs WHERE DATE(created_at) = date) as new_jobs,
        (SELECT COUNT(*) FROM applications WHERE DATE(created_at) = date) as new_applications
    FROM users
    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    GROUP BY DATE(created_at)
    ORDER BY date DESC
    LIMIT 30
    """
    cursor.execute(daily_query)
    daily_stats = cursor.fetchall()
    
    cursor.close()
    connection.close()
    
    return jsonify({
        'overall': stats,
        'daily': daily_stats,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/users')
def api_users():
    """API endpoint for users data"""
    if not session.get('logged_in'):
        return jsonify({'error': 'Unauthorized'}), 401
    
    connection = get_db_connection()
    if not connection:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = connection.cursor(dictionary=True)
    
    # Get filter parameters
    limit = request.args.get('limit', 100, type=int)
    offset = request.args.get('offset', 0, type=int)
    user_type = request.args.get('type')
    status = request.args.get('status')
    
    # Build query
    query = "SELECT * FROM users WHERE 1=1"
    params = []
    
    if user_type:
        query += " AND user_type = %s"
        params.append(user_type)
    
    if status:
        query += " AND status = %s"
        params.append(status)
    
    query += " ORDER BY created_at DESC LIMIT %s OFFSET %s"
    params.extend([limit, offset])
    
    cursor.execute(query, params)
    users = cursor.fetchall()
    
    # Get total count
    count_query = "SELECT COUNT(*) as total FROM users"
    cursor.execute(count_query)
    total = cursor.fetchone()['total']
    
    cursor.close()
    connection.close()
    
    return jsonify({
        'users': users,
        'total': total,
        'limit': limit,
        'offset': offset
    })

@app.route('/api/jobs')
def api_jobs():
    """API endpoint for jobs data"""
    if not session.get('logged_in'):
        return jsonify({'error': 'Unauthorized'}), 401
    
    connection = get_db_connection()
    if not connection:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = connection.cursor(dictionary=True)
    
    # Get filter parameters
    limit = request.args.get('limit', 100, type=int)
    offset = request.args.get('offset', 0, type=int)
    status = request.args.get('status')
    category = request.args.get('category')
    
    # Build query
    query = """
    SELECT j.*, c.name as company_name, 
           (SELECT COUNT(*) FROM applications WHERE job_id = j.id) as applications_count
    FROM jobs j
    LEFT JOIN companies c ON j.company_id = c.id
    WHERE 1=1
    """
    params = []
    
    if status:
        query += " AND j.status = %s"
        params.append(status)
    
    if category:
        query += " AND j.category = %s"
        params.append(category)
    
    query += " ORDER BY j.created_at DESC LIMIT %s OFFSET %s"
    params.extend([limit, offset])
    
    cursor.execute(query, params)
    jobs = cursor.fetchall()
    
    # Get total count
    count_query = "SELECT COUNT(*) as total FROM jobs"
    cursor.execute(count_query)
    total = cursor.fetchone()['total']
    
    cursor.close()
    connection.close()
    
    return jsonify({
        'jobs': jobs,
        'total': total,
        'limit': limit,
        'offset': offset
    })

@app.route('/api/messages')
def api_messages():
    """API endpoint for message logs"""
    if not session.get('logged_in'):
        return jsonify({'error': 'Unauthorized'}), 401
    
    connection = get_db_connection()
    if not connection:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = connection.cursor(dictionary=True)
    
    # Get recent messages
    query = """
    SELECT m.*, u.username, u.full_name
    FROM messages m
    LEFT JOIN users u ON m.user_id = u.id
    ORDER BY m.timestamp DESC
    LIMIT 100
    """
    cursor.execute(query)
    messages = cursor.fetchall()
    
    cursor.close()
    connection.close()
    
    return jsonify({'messages': messages})

@app.route('/api/broadcast', methods=['POST'])
def api_broadcast():
    """API endpoint to send broadcast message"""
    if not session.get('logged_in'):
        return jsonify({'error': 'Unauthorized'}), 401
    
    data = request.json
    message = data.get('message')
    
    if not message:
        return jsonify({'error': 'Message required'}), 400
    
    # In a real implementation, this would send message to all users
    # For now, just log it
    print(f"Broadcast message: {message}")
    
    return jsonify({
        'success': True,
        'message': 'Broadcast scheduled',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/users')
def users_page():
    """Users management page"""
    if not session.get('logged_in'):
        return redirect(url_for('login'))
    
    return render_template('users.html', username=session.get('username'))

@app.route('/jobs')
def jobs_page():
    """Jobs management page"""
    if not session.get('logged_in'):
        return redirect(url_for('login'))
    
    return render_template('jobs.html', username=session.get('username'))

@app.route('/messages')
def messages_page():
    """Message logs page"""
    if not session.get('logged_in'):
        return redirect(url_for('login'))
    
    return render_template('messages.html', username=session.get('username'))

@app.route('/settings')
def settings_page():
    """Settings page"""
    if not session.get('logged_in'):
        return redirect(url_for('login'))
    
    return render_template('settings.html', username=session.get('username'))

# Templates
@app.route('/templates/<template_name>')
def serve_template(template_name):
    """Serve HTML templates"""
    templates = {
        'login.html': '''
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ZewedJobs Dashboard - Login</title>
            <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
            <style>
                body {
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .login-card {
                    background: white;
                    border-radius: 15px;
                    box-shadow: 0 10px 40px rgba(0,0,0,0.1);
                    width: 100%;
                    max-width: 400px;
                }
                .login-header {
                    background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
                    color: white;
                    border-radius: 15px 15px 0 0;
                    padding: 30px;
                    text-align: center;
                }
                .login-body {
                    padding: 30px;
                }
                .logo {
                    font-size: 2.5rem;
                    margin-bottom: 10px;
                }
            </style>
        </head>
        <body>
            <div class="login-card">
                <div class="login-header">
                    <div class="logo">
                        <i class="fas fa-briefcase"></i>
                    </div>
                    <h3>ZewedJobs Dashboard</h3>
                    <p>Telegram Bot Analytics</p>
                </div>
                <div class="login-body">
                    <form method="POST" action="/login">
                        <div class="mb-3">
                            <label for="username" class="form-label">
                                <i class="fas fa-user me-2"></i>Username
                            </label>
                            <input type="text" class="form-control" id="username" name="username" 
                                   placeholder="Enter username" required autofocus>
                        </div>
                        <div class="mb-3">
                            <label for="password" class="form-label">
                                <i class="fas fa-lock me-2"></i>Password
                            </label>
                            <input type="password" class="form-control" id="password" name="password" 
                                   placeholder="Enter password" required>
                        </div>
                        <button type="submit" class="btn btn-primary w-100">
                            <i class="fas fa-sign-in-alt me-2"></i>Login
                        </button>
                        <div class="mt-3 text-center">
                            <small class="text-muted">
                                <i class="fas fa-info-circle me-1"></i>
                                Default: admin / admin123
                            </small>
                        </div>
                    </form>
                </div>
            </div>
            <script src="https://kit.fontawesome.com/your-fontawesome-kit.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
        </body>
        </html>
        ''',
        
        'dashboard.html': '''
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ZewedJobs Dashboard</title>
            <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
            <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
            <style>
                :root {
                    --primary-color: #2c3e50;
                    --secondary-color: #3498db;
                }
                body {
                    background-color: #f8f9fa;
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                }
                .sidebar {
                    background-color: var(--primary-color);
                    min-height: 100vh;
                    color: white;
                }
                .sidebar a {
                    color: #ecf0f1;
                    text-decoration: none;
                    padding: 10px 15px;
                    display: block;
                    border-radius: 5px;
                    margin-bottom: 5px;
                    transition: all 0.3s;
                }
                .sidebar a:hover, .sidebar a.active {
                    background-color: var(--secondary-color);
                    color: white;
                }
                .stat-card {
                    border-radius: 10px;
                    transition: transform 0.3s;
                    border: none;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                }
                .stat-card:hover {
                    transform: translateY(-5px);
                    box-shadow: 0 5px 15px rgba(0,0,0,0.2);
                }
                .stat-card i {
                    font-size: 2.5rem;
                    opacity: 0.8;
                }
                .table-hover tbody tr:hover {
                    background-color: rgba(52, 152, 219, 0.1);
                }
            </style>
        </head>
        <body>
            <div class="container-fluid">
                <div class="row">
                    <div class="col-md-3 col-lg-2 sidebar">
                        <div class="p-3">
                            <h3 class="text-center mb-4">
                                <i class="fas fa-chart-line"></i>
                                ZewedJobs
                            </h3>
                            <hr>
                            <a href="/dashboard" class="active">
                                <i class="fas fa-tachometer-alt"></i> Dashboard
                            </a>
                            <a href="/users">
                                <i class="fas fa-users"></i> Users
                            </a>
                            <a href="/jobs">
                                <i class="fas fa-briefcase"></i> Jobs
                            </a>
                            <a href="/messages">
                                <i class="fas fa-comments"></i> Messages
                            </a>
                            <a href="/settings">
                                <i class="fas fa-cog"></i> Settings
                            </a>
                            <hr>
                            <a href="/logout" class="text-danger">
                                <i class="fas fa-sign-out-alt"></i> Logout
                            </a>
                        </div>
                    </div>
                    
                    <div class="col-md-9 col-lg-10">
                        <nav class="navbar navbar-light bg-light">
                            <div class="container-fluid">
                                <span class="navbar-brand mb-0 h1">Dashboard</span>
                                <div class="d-flex align-items-center">
                                    <span class="me-3">
                                        <i class="fas fa-user-circle"></i> {{ username }}
                                    </span>
                                    <span class="badge bg-success">
                                        <i class="fas fa-circle me-1"></i> Online
                                    </span>
                                </div>
                            </div>
                        </nav>
                        
                        <div class="p-4">
                            <!-- Stats Cards -->
                            <div class="row mb-4">
                                <div class="col-md-3 mb-3">
                                    <div class="card stat-card border-start border-primary border-4">
                                        <div class="card-body">
                                            <div class="d-flex justify-content-between align-items-center">
                                                <div>
                                                    <h6 class="text-muted">Total Users</h6>
                                                    <h3>{{ stats.total_users }}</h3>
                                                </div>
                                                <i class="fas fa-users text-primary"></i>
                                            </div>
                                            <small class="text-success">
                                                <i class="fas fa-arrow-up"></i> 
                                                {{ stats.new_users_today }} new today
                                            </small>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-3 mb-3">
                                    <div class="card stat-card border-start border-success border-4">
                                        <div class="card-body">
                                            <div class="d-flex justify-content-between align-items-center">
                                                <div>
                                                    <h6 class="text-muted">Active Jobs</h6>
                                                    <h3>{{ stats.active_jobs }}</h3>
                                                </div>
                                                <i class="fas fa-briefcase text-success"></i>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-3 mb-3">
                                    <div class="card stat-card border-start border-info border-4">
                                        <div class="card-body">
                                            <div class="d-flex justify-content-between align-items-center">
                                                <div>
                                                    <h6 class="text-muted">Today's Applications</h6>
                                                    <h3>{{ stats.today_applications }}</h3>
                                                </div>
                                                <i class="fas fa-file-alt text-info"></i>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-3 mb-3">
                                    <div class="card stat-card border-start border-warning border-4">
                                        <div class="card-body">
                                            <div class="d-flex justify-content-between align-items-center">
                                                <div>
                                                    <h6 class="text-muted">Messages Today</h6>
                                                    <h3>{{ stats.messages_today }}</h3>
                                                </div>
                                                <i class="fas fa-comments text-warning"></i>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                            
                            <!-- Charts -->
                            <div class="row mb-4">
                                <div class="col-md-8">
                                    <div class="card">
                                        <div class="card-header">
                                            <h6 class="mb-0">User Growth (Last 7 Days)</h6>
                                        </div>
                                        <div class="card-body">
                                            <canvas id="userGrowthChart"></canvas>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-4">
                                    <div class="card">
                                        <div class="card-header">
                                            <h6 class="mb-0">Quick Actions</h6>
                                        </div>
                                        <div class="card-body">
                                            <button class="btn btn-primary w-100 mb-2" onclick="sendBroadcast()">
                                                <i class="fas fa-bullhorn me-2"></i> Send Broadcast
                                            </button>
                                            <button class="btn btn-success w-100 mb-2" onclick="refreshData()">
                                                <i class="fas fa-sync-alt me-2"></i> Refresh Data
                                            </button>
                                            <button class="btn btn-info w-100 mb-2" onclick="exportData()">
                                                <i class="fas fa-download me-2"></i> Export Data
                                            </button>
                                            <button class="btn btn-warning w-100" onclick="showLogs()">
                                                <i class="fas fa-file-alt me-2"></i> View Logs
                                            </button>
                                        </div>
                                    </div>
                                </div>
                            </div>
                            
                            <!-- Recent Users -->
                            <div class="row">
                                <div class="col-md-6 mb-4">
                                    <div class="card">
                                        <div class="card-header">
                                            <h6 class="mb-0">
                                                <i class="fas fa-users me-2"></i> Recent Users
                                            </h6>
                                        </div>
                                        <div class="card-body p-0">
                                            <div class="table-responsive">
                                                <table class="table table-hover mb-0">
                                                    <thead class="table-light">
                                                        <tr>
                                                            <th>Name</th>
                                                            <th>Type</th>
                                                            <th>Joined</th>
                                                        </tr>
                                                    </thead>
                                                    <tbody>
                                                        {% for user in recent_users %}
                                                        <tr>
                                                            <td>
                                                                <strong>{{ user.full_name or user.username }}</strong>
                                                                <br>
                                                                <small class="text-muted">@{{ user.username }}</small>
                                                            </td>
                                                            <td>
                                                                <span class="badge bg-{{ 'primary' if user.user_type == 'job_seeker' else 'success' }}">
                                                                    {{ user.user_type }}
                                                                </span>
                                                            </td>
                                                            <td>{{ user.created_at.strftime('%Y-%m-%d') }}</td>
                                                        </tr>
                                                        {% endfor %}
                                                    </tbody>
                                                </table>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                                
                                <!-- Recent Jobs -->
                                <div class="col-md-6 mb-4">
                                    <div class="card">
                                        <div class="card-header">
                                            <h6 class="mb-0">
                                                <i class="fas fa-briefcase me-2"></i> Recent Jobs
                                            </h6>
                                        </div>
                                        <div class="card-body p-0">
                                            <div class="table-responsive">
                                                <table class="table table-hover mb-0">
                                                    <thead class="table-light">
                                                        <tr>
                                                            <th>Title</th>
                                                            <th>Company</th>
                                                            <th>Status</th>
                                                        </tr>
                                                    </thead>
                                                    <tbody>
                                                        {% for job in recent_jobs %}
                                                        <tr>
                                                            <td>{{ job.title }}</td>
                                                            <td>{{ job.company_name }}</td>
                                                            <td>
                                                                <span class="badge bg-{{ 'success' if job.status == 'active' else 'warning' }}">
                                                                    {{ job.status }}
                                                                </span>
                                                            </td>
                                                        </tr>
                                                        {% endfor %}
                                                    </tbody>
                                                </table>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <script>
                // User growth chart
                const userGrowthData = {{ user_growth|tojson }};
                
                const ctx = document.getElementById('userGrowthChart').getContext('2d');
                const chart = new Chart(ctx, {
                    type: 'line',
                    data: {
                        labels: userGrowthData.map(item => item.date),
                        datasets: [{
                            label: 'New Users',
                            data: userGrowthData.map(item => item.count),
                            borderColor: '#3498db',
                            backgroundColor: 'rgba(52, 152, 219, 0.1)',
                            borderWidth: 2,
                            fill: true,
                            tension: 0.4
                        }]
                    },
                    options: {
                        responsive: true,
                        plugins: {
                            legend: {
                                position: 'top',
                            }
                        }
                    }
                });
                
                // Refresh data
                function refreshData() {
                    location.reload();
                }
                
                // Send broadcast
                function sendBroadcast() {
                    const message = prompt('Enter broadcast message:');
                    if (message) {
                        fetch('/api/broadcast', {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json',
                            },
                            body: JSON.stringify({ message: message })
                        })
                        .then(response => response.json())
                        .then(data => {
                            alert('Broadcast sent successfully!');
                        })
                        .catch(error => {
                            alert('Error sending broadcast');
                        });
                    }
                }
                
                // Export data
                function exportData() {
                    alert('Export feature coming soon!');
                }
                
                // Show logs
                function showLogs() {
                    window.open('/messages', '_blank');
                }
                
                // Auto refresh every 30 seconds
                setInterval(refreshData, 30000);
            </script>
        </body>
        </html>
        '''
    }
    
    return templates.get(template_name, 'Template not found')

if __name__ == '__main__':
    # Create logs directory
    os.makedirs('logs', exist_ok=True)
    
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('logs/web_dashboard.log'),
            logging.StreamHandler()
        ]
    )
    
    logger = logging.getLogger(__name__)
    logger.info("Starting ZewedJobs Web Dashboard...")
    
    app.run(host='0.0.0.0', port=5000, debug=True)
