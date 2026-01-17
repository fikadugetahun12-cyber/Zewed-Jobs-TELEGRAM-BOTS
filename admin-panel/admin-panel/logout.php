<?php
session_start();

// Log logout activity if user was logged in
if (isset($_SESSION['user_id'])) {
    require_once 'config/config.php';
    $log_stmt = $db->prepare("
        INSERT INTO admin_logs (admin_id, action, details) 
        VALUES (?, 'logout', 'User logged out from IP: ?')
    ");
    $log_stmt->execute([$_SESSION['user_id'], $_SERVER['REMOTE_ADDR']]);
}

// Destroy session
session_destroy();

// Redirect to login page
header('Location: login.php');
exit();
?>
