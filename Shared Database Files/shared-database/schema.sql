-- ZewedJobs Database Schema
-- Version: 2.0.0
-- Created: 2024-01-01

-- Create database if not exists
CREATE DATABASE IF NOT EXISTS zewedjobs_admin 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE zewedjobs_admin;

-- Admin Users Table
CREATE TABLE admin_users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    full_name VARCHAR(100),
    role ENUM('superadmin', 'admin', 'moderator') DEFAULT 'admin',
    status ENUM('active', 'inactive', 'suspended') DEFAULT 'active',
    last_login DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_admin_status (status),
    INDEX idx_admin_role (role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Companies Table
CREATE TABLE companies (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(200) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(20),
    website VARCHAR(200),
    industry VARCHAR(50),
    size ENUM('1-10', '11-50', '51-200', '201-500', '501-1000', '1000+'),
    description TEXT,
    address TEXT,
    logo VARCHAR(255),
    status ENUM('active', 'inactive', 'pending', 'deleted') DEFAULT 'active',
    verified BOOLEAN DEFAULT FALSE,
    created_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at DATETIME,
    INDEX idx_company_status (status),
    INDEX idx_company_industry (industry),
    INDEX idx_company_verified (verified),
    FOREIGN KEY (created_by) REFERENCES admin_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Jobs Table
CREATE TABLE jobs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    requirements TEXT,
    location VARCHAR(100),
    salary_min DECIMAL(12,2),
    salary_max DECIMAL(12,2),
    salary_currency VARCHAR(3) DEFAULT 'ETB',
    job_type ENUM('full-time', 'part-time', 'contract', 'internship', 'remote', 'freelance'),
    experience_level ENUM('entry', 'mid', 'senior', 'executive'),
    education_level VARCHAR(50),
    company_id INT NOT NULL,
    category VARCHAR(50),
    deadline DATE,
    status ENUM('active', 'inactive', 'pending', 'expired', 'filled', 'draft', 'deleted') DEFAULT 'active',
    views INT DEFAULT 0,
    applications_count INT DEFAULT 0,
    created_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at DATETIME,
    INDEX idx_job_status (status),
    INDEX idx_job_company (company_id),
    INDEX idx_job_category (category),
    INDEX idx_job_location (location),
    INDEX idx_job_type (job_type),
    INDEX idx_job_deadline (deadline),
    FULLTEXT idx_job_search (title, description, requirements, location),
    FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES admin_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Users Table (Telegram users)
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    telegram_id BIGINT UNIQUE NOT NULL,
    username VARCHAR(100),
    full_name VARCHAR(200),
    email VARCHAR(100),
    phone VARCHAR(20),
    profile_picture VARCHAR(255),
    profession VARCHAR(100),
    experience VARCHAR(50),
    education VARCHAR(100),
    skills TEXT,
    resume_file VARCHAR(255),
    location VARCHAR(100),
    expected_salary_min DECIMAL(12,2),
    expected_salary_max DECIMAL(12,2),
    user_type ENUM('job_seeker', 'employer', 'admin') DEFAULT 'job_seeker',
    status ENUM('active', 'inactive', 'suspended', 'banned') DEFAULT 'active',
    preferences JSON,
    notifications_enabled BOOLEAN DEFAULT TRUE,
    last_seen DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_telegram_id (telegram_id),
    INDEX idx_user_type (user_type),
    INDEX idx_user_status (status),
    INDEX idx_user_location (location)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Applications Table
CREATE TABLE applications (
    id INT PRIMARY KEY AUTO_INCREMENT,
    job_id INT NOT NULL,
    user_id INT NOT NULL,
    cover_letter TEXT,
    resume_file VARCHAR(255),
    status ENUM('pending', 'reviewed', 'shortlisted', 'interviewed', 'accepted', 'rejected', 'withdrawn') DEFAULT 'pending',
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reviewed_at DATETIME,
    reviewed_by INT,
    notes TEXT,
    rating TINYINT CHECK (rating >= 1 AND rating <= 5),
    INDEX idx_app_job (job_id),
    INDEX idx_app_user (user_id),
    INDEX idx_app_status (status),
    INDEX idx_app_date (applied_at),
    UNIQUE KEY unique_application (job_id, user_id),
    FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (reviewed_by) REFERENCES admin_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Messages Table (Bot conversations)
CREATE TABLE messages (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    message_type ENUM('text', 'photo', 'document', 'callback', 'command'),
    content TEXT,
    file_id VARCHAR(255),
    is_bot BOOLEAN DEFAULT FALSE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_msg_user (user_id),
    INDEX idx_msg_type (message_type),
    INDEX idx_msg_time (timestamp),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Job Alerts Table
CREATE TABLE job_alerts (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    keywords TEXT,
    location VARCHAR(100),
    category VARCHAR(50),
    job_type VARCHAR(50),
    min_salary DECIMAL(12,2),
    frequency ENUM('daily', 'weekly', 'instant') DEFAULT 'daily',
    last_sent DATETIME,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_alert_user (user_id),
    INDEX idx_alert_active (is_active),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Saved Jobs Table
CREATE TABLE saved_jobs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    job_id INT NOT NULL,
    saved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    INDEX idx_saved_user (user_id),
    INDEX idx_saved_job (job_id),
    UNIQUE KEY unique_saved_job (user_id, job_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Admin Logs Table
CREATE TABLE admin_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    admin_id INT,
    action VARCHAR(100) NOT NULL,
    details TEXT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_log_admin (admin_id),
    INDEX idx_log_action (action),
    INDEX idx_log_date (created_at),
    FOREIGN KEY (admin_id) REFERENCES admin_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- System Logs Table
CREATE TABLE system_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    level ENUM('info', 'warning', 'error', 'critical') DEFAULT 'info',
    component VARCHAR(100),
    message TEXT NOT NULL,
    details JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_log_level (level),
    INDEX idx_log_component (component),
    INDEX idx_log_date (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Settings Table
CREATE TABLE settings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    setting_type ENUM('string', 'integer', 'boolean', 'json', 'array') DEFAULT 'string',
    description TEXT,
    category VARCHAR(50),
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_setting_key (setting_key),
    INDEX idx_setting_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Backup Logs Table
CREATE TABLE backup_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    backup_type ENUM('full', 'incremental', 'schema', 'data') DEFAULT 'full',
    filename VARCHAR(255) NOT NULL,
    file_size BIGINT,
    status ENUM('success', 'failed', 'in_progress') DEFAULT 'in_progress',
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    INDEX idx_backup_type (backup_type),
    INDEX idx_backup_status (status),
    INDEX idx_backup_date (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create default admin user (password: admin123)
INSERT INTO admin_users (username, password_hash, email, full_name, role, status) 
VALUES (
    'admin', 
    '$2y$10$YourHashedPasswordHere', -- Use password_hash('admin123', PASSWORD_DEFAULT) in PHP
    'admin@zewedjobs.com', 
    'System Administrator', 
    'superadmin', 
    'active'
);

-- Insert initial settings
INSERT INTO settings (setting_key, setting_value, setting_type, description, category, is_public) VALUES
('site_name', 'ZewedJobs', 'string', 'Website name', 'general', TRUE),
('site_description', 'Ethiopian Job Portal', 'string', 'Website description', 'general', TRUE),
('site_url', 'https://zewedjobs.com', 'string', 'Website URL', 'general', TRUE),
('contact_email', 'contact@zewedjobs.com', 'string', 'Contact email', 'general', TRUE),
('support_email', 'support@zewedjobs.com', 'string', 'Support email', 'general', TRUE),
('default_currency', 'ETB', 'string', 'Default currency', 'finance', TRUE),
('jobs_per_page', '20', 'integer', 'Number of jobs per page', 'display', TRUE),
('max_job_duration', '90', 'integer', 'Maximum job duration in days', 'jobs', FALSE),
('application_cooldown', '24', 'integer', 'Hours between applications from same user', 'applications', FALSE),
('notification_enabled', 'true', 'boolean', 'Enable notifications', 'notifications', TRUE),
('backup_enabled', 'true', 'boolean', 'Enable automatic backups', 'backup', FALSE),
('backup_frequency', 'daily', 'string', 'Backup frequency', 'backup', FALSE),
('maintenance_mode', 'false', 'boolean', 'Maintenance mode status', 'system', TRUE),
('registration_enabled', 'true', 'boolean', 'Enable user registration', 'users', TRUE),
('job_post_enabled', 'true', 'boolean', 'Enable job posting', 'jobs', TRUE);

-- Create sample companies
INSERT INTO companies (name, email, phone, website, industry, size, description, address, status, verified) VALUES
('Ethio Telecom', 'careers@ethiotelecom.et', '+251 11 123 4567', 'https://www.ethiotelecom.et', 'telecom', '1000+', 'Leading telecommunications company in Ethiopia', 'Addis Ababa, Ethiopia', 'active', TRUE),
('Dashen Bank', 'hr@dashenbanksc.com', '+251 11 555 1234', 'https://www.dashenbanksc.com', 'finance', '1000+', 'Private commercial bank in Ethiopia', 'Addis Ababa, Ethiopia', 'active', TRUE),
('Kifiya Financial Technology', 'info@kifiya.com', '+251 11 777 8888', 'https://www.kifiya.com', 'IT', '201-500', 'Fintech company providing digital solutions', 'Addis Ababa, Ethiopia', 'active', TRUE),
('Ministry of Innovation and Technology', 'jobs@mintech.gov.et', '+251 11 999 0000', 'https://www.mintech.gov.et', 'government', '1000+', 'Government ministry for innovation and technology', 'Addis Ababa, Ethiopia', 'active', TRUE);

-- Create sample jobs
INSERT INTO jobs (title, description, requirements, location, salary_min, salary_max, job_type, experience_level, company_id, category, deadline, status) VALUES
('Software Developer', 'Develop and maintain web applications using modern technologies.', 'BSc in Computer Science, 2+ years experience, Python/Django, React', 'Addis Ababa', 25000, 40000, 'full-time', 'mid', 1, 'IT', DATE_ADD(CURDATE(), INTERVAL 30 DAY), 'active'),
('Marketing Manager', 'Lead marketing team and develop strategies for brand growth.', 'BA in Marketing, 5+ years experience, Digital marketing skills', 'Addis Ababa', 30000, 50000, 'full-time', 'senior', 2, 'sales', DATE_ADD(CURDATE(), INTERVAL 45 DAY), 'active'),
('Data Analyst', 'Analyze business data and provide insights for decision making.', 'BSc in Statistics/Mathematics, SQL, Python, Excel', 'Remote', 20000, 35000, 'remote', 'entry', 3, 'IT', DATE_ADD(CURDATE(), INTERVAL 60 DAY), 'active'),
('HR Specialist', 'Manage recruitment, employee relations, and HR processes.', 'BA in Human Resources, 3+ years HR experience', 'Addis Ababa', 18000, 30000, 'full-time', 'mid', 4, 'hr', DATE_ADD(CURDATE(), INTERVAL 20 DAY), 'active');

-- Create indexes for better performance
CREATE INDEX idx_jobs_salary ON jobs(salary_min, salary_max);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_applications_job_user ON applications(job_id, user_id);
CREATE INDEX idx_messages_user_time ON messages(user_id, timestamp);
CREATE INDEX idx_alerts_frequency ON job_alerts(frequency, is_active);

-- Create views for reports
CREATE VIEW job_statistics AS
SELECT 
    c.name as company_name,
    COUNT(j.id) as total_jobs,
    SUM(j.applications_count) as total_applications,
    AVG(j.salary_min) as avg_min_salary,
    AVG(j.salary_max) as avg_max_salary
FROM companies c
LEFT JOIN jobs j ON c.id = j.company_id AND j.status = 'active'
GROUP BY c.id, c.name;

CREATE VIEW user_statistics AS
SELECT 
    user_type,
    COUNT(*) as total_users,
    SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) as active_users,
    AVG(TIMESTAMPDIFF(DAY, created_at, NOW())) as avg_account_age
FROM users
GROUP BY user_type;

-- Create stored procedures
DELIMITER //

CREATE PROCEDURE GetActiveJobs(IN p_category VARCHAR(50), IN p_location VARCHAR(100))
BEGIN
    SELECT j.*, c.name as company_name
    FROM jobs j
    LEFT JOIN companies c ON j.company_id = c.id
    WHERE j.status = 'active'
      AND j.deadline >= CURDATE()
      AND (p_category IS NULL OR j.category = p_category)
      AND (p_location IS NULL OR j.location LIKE CONCAT('%', p_location, '%'))
    ORDER BY j.created_at DESC
    LIMIT 100;
END //

CREATE PROCEDURE GetUserApplications(IN p_user_id INT)
BEGIN
    SELECT a.*, j.title as job_title, c.name as company_name
    FROM applications a
    JOIN jobs j ON a.job_id = j.id
    JOIN companies c ON j.company_id = c.id
    WHERE a.user_id = p_user_id
    ORDER BY a.applied_at DESC;
END //

CREATE PROCEDURE UpdateJobStats(IN p_job_id INT)
BEGIN
    DECLARE app_count INT;
    
    SELECT COUNT(*) INTO app_count
    FROM applications
    WHERE job_id = p_job_id;
    
    UPDATE jobs 
    SET applications_count = app_count,
        updated_at = NOW()
    WHERE id = p_job_id;
END //

DELIMITER ;

-- Create triggers
DELIMITER //

CREATE TRIGGER after_application_insert
AFTER INSERT ON applications
FOR EACH ROW
BEGIN
    CALL UpdateJobStats(NEW.job_id);
    
    INSERT INTO system_logs (level, component, message, details)
    VALUES ('info', 'applications', 'New application submitted', 
            JSON_OBJECT('job_id', NEW.job_id, 'user_id', NEW.user_id));
END //

CREATE TRIGGER after_job_update
AFTER UPDATE ON jobs
FOR EACH ROW
BEGIN
    IF NEW.deadline < CURDATE() AND NEW.status = 'active' THEN
        UPDATE jobs SET status = 'expired' WHERE id = NEW.id;
        
        INSERT INTO system_logs (level, component, message, details)
        VALUES ('info', 'jobs', 'Job auto-expired', 
                JSON_OBJECT('job_id', NEW.id, 'title', NEW.title));
    END IF;
END //

DELIMITER ;

-- Create events for maintenance
DELIMITER //

CREATE EVENT IF NOT EXISTS cleanup_expired_jobs
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY
DO
BEGIN
    UPDATE jobs 
    SET status = 'expired'
    WHERE status = 'active' 
      AND deadline < CURDATE();
    
    INSERT INTO system_logs (level, component, message)
    VALUES ('info', 'maintenance', 'Expired jobs cleanup completed');
END //

CREATE EVENT IF NOT EXISTS update_user_last_seen
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    UPDATE users u
    JOIN (
        SELECT user_id, MAX(timestamp) as last_active
        FROM messages
        WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 7 DAY)
        GROUP BY user_id
    ) m ON u.id = m.user_id
    SET u.last_seen = m.last_active
    WHERE u.last_seen IS NULL OR u.last_seen < m.last_active;
END //

DELIMITER ;

-- Grant permissions (adjust as needed for your setup)
-- CREATE USER 'zewedjobs_user'@'localhost' IDENTIFIED BY 'strong_password_here';
-- GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON zewedjobs_admin.* TO 'zewedjobs_user'@'localhost';
-- FLUSH PRIVILEGES;

COMMIT;
