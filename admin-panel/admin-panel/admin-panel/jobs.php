<?php
session_start();
require_once 'config/config.php';

// Check if user is logged in
if (!isset($_SESSION['user_id'])) {
    header('Location: login.php');
    exit();
}

// Handle actions
$action = $_GET['action'] ?? '';
$id = $_GET['id'] ?? 0;

// Add new job
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'add') {
    $title = $_POST['title'];
    $description = $_POST['description'];
    $requirements = $_POST['requirements'];
    $location = $_POST['location'];
    $salary_min = $_POST['salary_min'];
    $salary_max = $_POST['salary_max'];
    $job_type = $_POST['job_type'];
    $experience_level = $_POST['experience_level'];
    $company_id = $_POST['company_id'];
    $category = $_POST['category'];
    $deadline = $_POST['deadline'];
    $status = $_POST['status'];
    
    $stmt = $db->prepare("
        INSERT INTO jobs (
            title, description, requirements, location, salary_min, salary_max,
            job_type, experience_level, company_id, category, deadline, status,
            created_by, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
    ");
    
    $stmt->execute([
        $title, $description, $requirements, $location, $salary_min, $salary_max,
        $job_type, $experience_level, $company_id, $category, $deadline, $status,
        $_SESSION['user_id']
    ]);
    
    header('Location: jobs.php?success=Job added successfully');
    exit();
}

// Update job
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'edit') {
    $title = $_POST['title'];
    $description = $_POST['description'];
    $requirements = $_POST['requirements'];
    $location = $_POST['location'];
    $salary_min = $_POST['salary_min'];
    $salary_max = $_POST['salary_max'];
    $job_type = $_POST['job_type'];
    $experience_level = $_POST['experience_level'];
    $company_id = $_POST['company_id'];
    $category = $_POST['category'];
    $deadline = $_POST['deadline'];
    $status = $_POST['status'];
    
    $stmt = $db->prepare("
        UPDATE jobs SET
            title = ?, description = ?, requirements = ?, location = ?,
            salary_min = ?, salary_max = ?, job_type = ?, experience_level = ?,
            company_id = ?, category = ?, deadline = ?, status = ?,
            updated_at = NOW()
        WHERE id = ?
    ");
    
    $stmt->execute([
        $title, $description, $requirements, $location, $salary_min, $salary_max,
        $job_type, $experience_level, $company_id, $category, $deadline, $status,
        $id
    ]);
    
    header('Location: jobs.php?success=Job updated successfully');
    exit();
}

// Delete job
if ($action === 'delete' && $id > 0) {
    $stmt = $db->prepare("UPDATE jobs SET status = 'deleted', deleted_at = NOW() WHERE id = ?");
    $stmt->execute([$id]);
    header('Location: jobs.php?success=Job deleted successfully');
    exit();
}

// Get jobs with filters
$filter_status = $_GET['status'] ?? '';
$filter_category = $_GET['category'] ?? '';
$filter_company = $_GET['company'] ?? '';

$query = "
    SELECT j.*, c.name as company_name, 
           (SELECT COUNT(*) FROM applications WHERE job_id = j.id) as applications_count
    FROM jobs j
    LEFT JOIN companies c ON j.company_id = c.id
    WHERE 1=1
";

$params = [];

if ($filter_status) {
    $query .= " AND j.status = ?";
    $params[] = $filter_status;
}

if ($filter_category) {
    $query .= " AND j.category = ?";
    $params[] = $filter_category;
}

if ($filter_company) {
    $query .= " AND j.company_id = ?";
    $params[] = $filter_company;
}

$query .= " ORDER BY j.created_at DESC";

$stmt = $db->prepare($query);
$stmt->execute($params);
$jobs = $stmt->fetchAll();

// Get companies for dropdown
$companies = $db->query("SELECT id, name FROM companies WHERE status = 'active' ORDER BY name")->fetchAll();

// Get job details for editing
$job = null;
if ($action === 'edit' && $id > 0) {
    $stmt = $db->prepare("SELECT * FROM jobs WHERE id = ?");
    $stmt->execute([$id]);
    $job = $stmt->fetch();
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Jobs Management - ZewedJobs Admin</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <link rel="stylesheet" href="https://cdn.datatables.net/1.11.5/css/dataTables.bootstrap5.min.css">
    <style>
        .job-card {
            border-radius: 10px;
            transition: all 0.3s;
            border: 1px solid #e0e0e0;
        }
        .job-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
        }
        .salary-badge {
            background-color: #e3f2fd;
            color: #1976d2;
            padding: 3px 10px;
            border-radius: 15px;
            font-weight: 500;
        }
        .filter-card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .form-label {
            font-weight: 500;
            color: #495057;
        }
        .table-actions {
            white-space: nowrap;
        }
        .badge-status {
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85rem;
        }
        .badge-active { background-color: #d4edda; color: #155724; }
        .badge-inactive { background-color: #f8d7da; color: #721c24; }
        .badge-pending { background-color: #fff3cd; color: #856404; }
        .badge-draft { background-color: #e2e3e5; color: #383d41; }
        .badge-expired { background-color: #d1ecf1; color: #0c5460; }
    </style>
</head>
<body>
    <?php include 'includes/header.php'; ?>
    
    <div class="container-fluid mt-4">
        <div class="row">
            <?php include 'includes/sidebar.php'; ?>
            
            <main class="col-md-9 ms-sm-auto col-lg-10 px-md-4">
                <!-- Header -->
                <div class="d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom">
                    <h1 class="h2">
                        <i class="fas fa-briefcase me-2"></i>Jobs Management
                    </h1>
                    <div class="btn-toolbar mb-2 mb-md-0">
                        <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#addJobModal">
                            <i class="fas fa-plus-circle me-1"></i> Add New Job
                        </button>
                    </div>
                </div>

                <!-- Success Message -->
                <?php if (isset($_GET['success'])): ?>
                    <div class="alert alert-success alert-dismissible fade show" role="alert">
                        <?php echo htmlspecialchars($_GET['success']); ?>
                        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                    </div>
                <?php endif; ?>

                <!-- Filters -->
                <div class="filter-card mb-4">
                    <form method="GET" class="row g-3">
                        <div class="col-md-3">
                            <label class="form-label">Status</label>
                            <select name="status" class="form-select">
                                <option value="">All Status</option>
                                <option value="active" <?php echo $filter_status === 'active' ? 'selected' : ''; ?>>Active</option>
                                <option value="inactive" <?php echo $filter_status === 'inactive' ? 'selected' : ''; ?>>Inactive</option>
                                <option value="pending" <?php echo $filter_status === 'pending' ? 'selected' : ''; ?>>Pending</option>
                                <option value="expired" <?php echo $filter_status === 'expired' ? 'selected' : ''; ?>>Expired</option>
                            </select>
                        </div>
                        <div class="col-md-3">
                            <label class="form-label">Category</label>
                            <select name="category" class="form-select">
                                <option value="">All Categories</option>
                                <option value="IT" <?php echo $filter_category === 'IT' ? 'selected' : ''; ?>>IT & Technology</option>
                                <option value="engineering" <?php echo $filter_category === 'engineering' ? 'selected' : ''; ?>>Engineering</option>
                                <option value="healthcare" <?php echo $filter_category === 'healthcare' ? 'selected' : ''; ?>>Healthcare</option>
                                <option value="education" <?php echo $filter_category === 'education' ? 'selected' : ''; ?>>Education</option>
                                <option value="sales" <?php echo $filter_category === 'sales' ? 'selected' : ''; ?>>Sales & Marketing</option>
                                <option value="finance" <?php echo $filter_category === 'finance' ? 'selected' : ''; ?>>Finance</option>
                            </select>
                        </div>
                        <div class="col-md-3">
                            <label class="form-label">Company</label>
                            <select name="company" class="form-select">
                                <option value="">All Companies</option>
                                <?php foreach ($companies as $company): ?>
                                    <option value="<?php echo $company['id']; ?>" 
                                        <?php echo $filter_company == $company['id'] ? 'selected' : ''; ?>>
                                        <?php echo htmlspecialchars($company['name']); ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        <div class="col-md-3 d-flex align-items-end">
                            <button type="submit" class="btn btn-primary w-100">
                                <i class="fas fa-filter me-1"></i> Filter
                            </button>
                            <a href="jobs.php" class="btn btn-outline-secondary ms-2">
                                <i class="fas fa-times"></i>
                            </a>
                        </div>
                    </form>
                </div>

                <!-- Jobs Table -->
                <div class="card">
                    <div class="card-body">
                        <div class="table-responsive">
                            <table class="table table-hover" id="jobsTable">
                                <thead>
                                    <tr>
                                        <th>ID</th>
                                        <th>Title</th>
                                        <th>Company</th>
                                        <th>Location</th>
                                        <th>Salary</th>
                                        <th>Applications</th>
                                        <th>Deadline</th>
                                        <th>Status</th>
                                        <th>Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php foreach ($jobs as $job_item): ?>
                                    <tr>
                                        <td>#<?php echo $job_item['id']; ?></td>
                                        <td>
                                            <strong><?php echo htmlspecialchars($job_item['title']); ?></strong>
                                            <br>
                                            <small class="text-muted">
                                                <?php echo htmlspecialchars($job_item['category']); ?> • 
                                                <?php echo ucfirst($job_item['job_type']); ?>
                                            </small>
                                        </td>
                                        <td><?php echo htmlspecialchars($job_item['company_name']); ?></td>
                                        <td><?php echo htmlspecialchars($job_item['location']); ?></td>
                                        <td>
                                            <?php if ($job_item['salary_min']): ?>
                                                <span class="salary-badge">
                                                    ETB <?php echo number_format($job_item['salary_min']); ?>
                                                    <?php if ($job_item['salary_max']): ?>
                                                        - <?php echo number_format($job_item['salary_max']); ?>
                                                    <?php endif; ?>
                                                </span>
                                            <?php else: ?>
                                                <span class="text-muted">Negotiable</span>
                                            <?php endif; ?>
                                        </td>
                                        <td>
                                            <span class="badge bg-info">
                                                <?php echo $job_item['applications_count']; ?> apps
                                            </span>
                                        </td>
                                        <td>
                                            <?php echo date('M d, Y', strtotime($job_item['deadline'])); ?>
                                        </td>
                                        <td>
                                            <span class="badge-status badge-<?php echo $job_item['status']; ?>">
                                                <?php echo ucfirst($job_item['status']); ?>
                                            </span>
                                        </td>
                                        <td class="table-actions">
                                            <a href="job_details.php?id=<?php echo $job_item['id']; ?>" 
                                               class="btn btn-sm btn-outline-primary" title="View">
                                                <i class="fas fa-eye"></i>
                                            </a>
                                            <a href="jobs.php?action=edit&id=<?php echo $job_item['id']; ?>" 
                                               class="btn btn-sm btn-outline-warning" title="Edit">
                                                <i class="fas fa-edit"></i>
                                            </a>
                                            <a href="jobs.php?action=delete&id=<?php echo $job_item['id']; ?>" 
                                               class="btn btn-sm btn-outline-danger" 
                                               onclick="return confirm('Are you sure you want to delete this job?')"
                                               title="Delete">
                                                <i class="fas fa-trash"></i>
                                            </a>
                                            <a href="applications.php?job_id=<?php echo $job_item['id']; ?>" 
                                               class="btn btn-sm btn-outline-info" title="Applications">
                                                <i class="fas fa-file-alt"></i>
                                            </a>
                                        </td>
                                    </tr>
                                    <?php endforeach; ?>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </main>
        </div>
    </div>

    <!-- Add Job Modal -->
    <div class="modal fade" id="addJobModal" tabindex="-1" aria-labelledby="addJobModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="addJobModalLabel">
                        <i class="fas fa-plus-circle me-2"></i>Add New Job
                    </h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <form method="POST" action="jobs.php?action=add">
                    <div class="modal-body">
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Job Title *</label>
                                <input type="text" class="form-control" name="title" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Company *</label>
                                <select class="form-select" name="company_id" required>
                                    <option value="">Select Company</option>
                                    <?php foreach ($companies as $company): ?>
                                        <option value="<?php echo $company['id']; ?>">
                                            <?php echo htmlspecialchars($company['name']); ?>
                                        </option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Job Type</label>
                                <select class="form-select" name="job_type">
                                    <option value="full-time">Full Time</option>
                                    <option value="part-time">Part Time</option>
                                    <option value="contract">Contract</option>
                                    <option value="internship">Internship</option>
                                    <option value="remote">Remote</option>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Experience Level</label>
                                <select class="form-select" name="experience_level">
                                    <option value="entry">Entry Level</option>
                                    <option value="mid">Mid Level</option>
                                    <option value="senior">Senior Level</option>
                                    <option value="executive">Executive</option>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Category</label>
                                <select class="form-select" name="category">
                                    <option value="IT">IT & Technology</option>
                                    <option value="engineering">Engineering</option>
                                    <option value="healthcare">Healthcare</option>
                                    <option value="education">Education</option>
                                    <option value="sales">Sales & Marketing</option>
                                    <option value="finance">Finance</option>
                                    <option value="other">Other</option>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Location</label>
                                <input type="text" class="form-control" name="location" placeholder="e.g., Addis Ababa">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Min Salary (ETB)</label>
                                <input type="number" class="form-control" name="salary_min" min="0" step="1000">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Max Salary (ETB)</label>
                                <input type="number" class="form-control" name="salary_max" min="0" step="1000">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Deadline</label>
                                <input type="date" class="form-control" name="deadline" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Status</label>
                                <select class="form-select" name="status">
                                    <option value="active">Active</option>
                                    <option value="pending">Pending</option>
                                    <option value="draft">Draft</option>
                                    <option value="inactive">Inactive</option>
                                </select>
                            </div>
                            <div class="col-12 mb-3">
                                <label class="form-label">Job Description *</label>
                                <textarea class="form-control" name="description" rows="4" required></textarea>
                            </div>
                            <div class="col-12 mb-3">
                                <label class="form-label">Requirements</label>
                                <textarea class="form-control" name="requirements" rows="3"></textarea>
                            </div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                        <button type="submit" class="btn btn-primary">Save Job</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <!-- Edit Job Modal (if editing) -->
    <?php if ($action === 'edit' && $job): ?>
    <div class="modal fade show" id="editJobModal" tabindex="-1" style="display: block; padding-right: 17px;">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">
                        <i class="fas fa-edit me-2"></i>Edit Job
                    </h5>
                    <a href="jobs.php" class="btn-close"></a>
                </div>
                <form method="POST" action="jobs.php?action=edit&id=<?php echo $id; ?>">
                    <div class="modal-body">
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Job Title *</label>
                                <input type="text" class="form-control" name="title" 
                                       value="<?php echo htmlspecialchars($job['title']); ?>" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Company *</label>
                                <select class="form-select" name="company_id" required>
                                    <?php foreach ($companies as $company): ?>
                                        <option value="<?php echo $company['id']; ?>"
                                            <?php echo $job['company_id'] == $company['id'] ? 'selected' : ''; ?>>
                                            <?php echo htmlspecialchars($company['name']); ?>
                                        </option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Job Type</label>
                                <select class="form-select" name="job_type">
                                    <option value="full-time" <?php echo $job['job_type'] == 'full-time' ? 'selected' : ''; ?>>Full Time</option>
                                    <option value="part-time" <?php echo $job['job_type'] == 'part-time' ? 'selected' : ''; ?>>Part Time</option>
                                    <option value="contract" <?php echo $job['job_type'] == 'contract' ? 'selected' : ''; ?>>Contract</option>
                                    <option value="internship" <?php echo $job['job_type'] == 'internship' ? 'selected' : ''; ?>>Internship</option>
                                    <option value="remote" <?php echo $job['job_type'] == 'remote' ? 'selected' : ''; ?>>Remote</option>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Experience Level</label>
                                <select class="form-select" name="experience_level">
                                    <option value="entry" <?php echo $job['experience_level'] == 'entry' ? 'selected' : ''; ?>>Entry Level</option>
                                    <option value="mid" <?php echo $job['experience_level'] == 'mid' ? 'selected' : ''; ?>>Mid Level</option>
                                    <option value="senior" <?php echo $job['experience_level'] == 'senior' ? 'selected' : ''; ?>>Senior Level</option>
                                    <option value="executive" <?php echo $job['experience_level'] == 'executive' ? 'selected' : ''; ?>>Executive</option>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Category</label>
                                <select class="form-select" name="category">
                                    <option value="IT" <?php echo $job['category'] == 'IT' ? 'selected' : ''; ?>>IT & Technology</option>
                                    <option value="engineering" <?php echo $job['category'] == 'engineering' ? 'selected' : ''; ?>>Engineering</option>
                                    <option value="healthcare" <?php echo $job['category'] == 'healthcare' ? 'selected' : ''; ?>>Healthcare</option>
                                    <option value="education" <?php echo $job['category'] == 'education' ? 'selected' : ''; ?>>Education</option>
                                    <option value="sales" <?php echo $job['category'] == 'sales' ? 'selected' : ''; ?>>Sales & Marketing</option>
                                    <option value="finance" <?php echo $job['category'] == 'finance' ? 'selected' : ''; ?>>Finance</option>
                                    <option value="other" <?php echo $job['category'] == 'other' ? 'selected' : ''; ?>>Other</option>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Location</label>
                                <input type="text" class="form-control" name="location" 
                                       value="<?php echo htmlspecialchars($job['location']); ?>">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Min Salary (ETB)</label>
                                <input type="number" class="form-control" name="salary_min" 
                                       value="<?php echo $job['salary_min']; ?>" min="0" step="1000">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Max Salary (ETB)</label>
                                <input type="number" class="form-control" name="salary_max" 
                                       value="<?php echo $job['salary_max']; ?>" min="0" step="1000">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Deadline</label>
                                <input type="date" class="form-control" name="deadline" 
                                       value="<?php echo $job['deadline']; ?>" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label class="form-label">Status</label>
                                <select class="form-select" name="status">
                                    <option value="active" <?php echo $job['status'] == 'active' ? 'selected' : ''; ?>>Active</option>
                                    <option value="pending" <?php echo $job['status'] == 'pending' ? 'selected' : ''; ?>>Pending</option>
                                    <option value="draft" <?php echo $job['status'] == 'draft' ? 'selected' : ''; ?>>Draft</option>
                                    <option value="inactive" <?php echo $job['status'] == 'inactive' ? 'selected' : ''; ?>>Inactive</option>
                                </select>
                            </div>
                            <div class="col-12 mb-3">
                                <label class="form-label">Job Description *</label>
                                <textarea class="form-control" name="description" rows="4" required><?php echo htmlspecialchars($job['description']); ?></textarea>
                            </div>
                            <div class="col-12 mb-3">
                                <label class="form-label">Requirements</label>
                                <textarea class="form-control" name="requirements" rows="3"><?php echo htmlspecialchars($job['requirements']); ?></textarea>
                            </div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <a href="jobs.php" class="btn btn-secondary">Cancel</a>
                        <button type="submit" class="btn btn-primary">Update Job</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
    <div class="modal-backdrop fade show"></div>
    <?php endif; ?>

    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/dataTables.bootstrap5.min.js"></script>
    <script>
        $(document).ready(function() {
            $('#jobsTable').DataTable({
                pageLength: 25,
                order: [[0, 'desc']]
            });
            
            <?php if ($action === 'edit' && $job): ?>
                $('#editJobModal').modal('show');
            <?php endif; ?>
        });
    </script>
</body>
</html>
