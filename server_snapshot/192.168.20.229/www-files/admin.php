<?php
/**
 * File Manager - Administrative Interface
 * Browse, upload, delete files in /var/www/files/
 * Password-protected with change password support
 * Multi-language: ru, en
 * Trash bin with auto-cleanup
 */

$BASE_DIR = '/var/www/files';
$LANG_DIR = $BASE_DIR . '/.lang';
$TRASH_DIR = $BASE_DIR . '/.trash';
$TRASH_META_DIR = $TRASH_DIR . '/.meta';
$RETENTION_FILE = $TRASH_DIR . '/.retention_days';
$TRASH_RETENTION_DAYS = file_exists($RETENTION_FILE) ? max(1, intval(trim(file_get_contents($RETENTION_FILE)))) : 30;
$MAX_UPLOAD = 100 * 1024 * 1024; // 100MB
$PASSWORD_FILE = $BASE_DIR . '/.admin_password';
$AVAILABLE_LANGS = ['ru' => 'RU', 'en' => 'EN'];
$DEFAULT_LANG = 'ru';
$SETTINGS_FILE = $BASE_DIR . '/.settings.json';
$settings = file_exists($SETTINGS_FILE) ? json_decode(file_get_contents($SETTINGS_FILE), true) : [];

// Set timezone
if (!empty($settings['timezone']) && in_array($settings['timezone'], timezone_identifiers_list())) {
    date_default_timezone_set($settings['timezone']);
} elseif (file_exists('/etc/timezone')) {
    $tz = trim(file_get_contents('/etc/timezone'));
    if (!empty($tz) && in_array($tz, timezone_identifiers_list())) {
        date_default_timezone_set($tz);
    }
} elseif (file_exists('/etc/localtime') && is_link('/etc/localtime')) {
    $link = readlink('/etc/localtime');
    $parts = explode('/zoneinfo/', $link);
    if (count($parts) > 1) {
        $tz = $parts[1];
        if (!empty($tz) && in_array($tz, timezone_identifiers_list())) {
            date_default_timezone_set($tz);
        }
    }
}
$server_tz = date_default_timezone_get();

// Initialize password file if not exists
if (!file_exists($PASSWORD_FILE)) {
    file_put_contents($PASSWORD_FILE, password_hash('REDACTED', PASSWORD_DEFAULT));
    chmod($PASSWORD_FILE, 0600);
    chown($PASSWORD_FILE, 'www-data');
}

// Initialize trash dirs
if (!is_dir($TRASH_DIR)) { mkdir($TRASH_DIR, 0755, true); }
if (!is_dir($TRASH_META_DIR)) { mkdir($TRASH_META_DIR, 0755, true); }

// Session
session_start();
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}
$csrf = $_SESSION['csrf_token'];

// Language: GET param (for login page switch) > settings file > default
if (isset($_GET['lang']) && array_key_exists($_GET['lang'], $AVAILABLE_LANGS)) {
    $current_lang = $_GET['lang'];
} elseif (isset($settings['lang']) && array_key_exists($settings['lang'], $AVAILABLE_LANGS)) {
    $current_lang = $settings['lang'];
} else {
    $current_lang = $DEFAULT_LANG;
}
$lang_file = $LANG_DIR . '/' . $current_lang . '.php';
if (file_exists($lang_file)) {
    $t = require $lang_file;
} else {
    $t = require $LANG_DIR . '/' . $DEFAULT_LANG . '.php';
}

function __($key) {
    global $t;
    return isset($t[$key]) ? $t[$key] : $key;
}

// ---- AUTH ----
function is_logged_in() {
    return isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true;
}

function verify_password($password) {
    global $PASSWORD_FILE;
    $hash = trim(file_get_contents($PASSWORD_FILE));
    return password_verify($password, $hash);
}

function change_password($new_password) {
    global $PASSWORD_FILE;
    return file_put_contents($PASSWORD_FILE, password_hash($new_password, PASSWORD_DEFAULT)) !== false;
}

// Handle login
$login_error = '';
if (isset($_POST['action']) && $_POST['action'] === 'login') {
    $password = isset($_POST['password']) ? $_POST['password'] : '';
    if (verify_password($password)) {
        $_SESSION['admin_logged_in'] = true;
        header('Location: ' . $_SERVER['PHP_SELF']);
        exit;
    } else {
        $login_error = __('wrong_password');
    }
}

// Handle logout
if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: ' . $_SERVER['PHP_SELF']);
    exit;
}

// Show login page if not logged in
if (!is_logged_in()) {
    show_login_page($login_error);
    exit;
}

// ---- FUNCTIONS ----
function check_csrf() {
    if (!isset($_POST['csrf']) || $_POST['csrf'] !== $_SESSION['csrf_token']) {
        die(__('invalid_csrf'));
    }
}

function safe_path($base, $path) {
    $full = realpath($base . '/' . $path);
    if ($full === false || strpos($full, realpath($base)) !== 0) {
        return false;
    }
    return $full;
}

function format_size($bytes) {
    if ($bytes >= 1073741824) return round($bytes / 1073741824, 2) . ' GB';
    if ($bytes >= 1048576) return round($bytes / 1048576, 2) . ' MB';
    if ($bytes >= 1024) return round($bytes / 1024, 2) . ' KB';
    return $bytes . ' B';
}

function move_to_trash($full_path, $rel_path) {
    global $TRASH_DIR, $TRASH_META_DIR;
    $trash_id = uniqid('trash_', true);
    $basename = basename($full_path);
    $trash_dest = $TRASH_DIR . '/' . $trash_id . '_' . $basename;

    // Save metadata
    $meta = [
        'original_path' => $rel_path,
        'original_name' => $basename,
        'deleted_at' => time(),
        'mtime' => filemtime($full_path),
        'is_dir' => is_dir($full_path),
    ];
    file_put_contents($TRASH_META_DIR . '/' . $trash_id . '.json', json_encode($meta, JSON_UNESCAPED_UNICODE));

    return rename($full_path, $trash_dest);
}

function get_trash_items() {
    global $TRASH_META_DIR, $TRASH_DIR;
    $items = [];
    if (!is_dir($TRASH_META_DIR)) return $items;

    foreach (glob($TRASH_META_DIR . '/*.json') as $meta_file) {
        $trash_id = basename($meta_file, '.json');
        $meta = json_decode(file_get_contents($meta_file), true);
        if (!$meta) continue;

        // Find matching trash file
        $pattern = $TRASH_DIR . '/' . $trash_id . '_*';
        $matches = glob($pattern);
        if (empty($matches)) {
            // Orphaned meta, remove
            unlink($meta_file);
            continue;
        }
        $trash_path = $matches[0];
        $size = is_dir($trash_path) ? get_dir_size($trash_path) : filesize($trash_path);

        $items[] = [
            'id' => $trash_id,
            'name' => $meta['original_name'],
            'original_path' => $meta['original_path'],
            'deleted_at' => $meta['deleted_at'],
            'mtime' => isset($meta['mtime']) ? $meta['mtime'] : 0,
            'is_dir' => $meta['is_dir'],
            'size' => $size,
            'trash_path' => $trash_path,
        ];
    }

    // Sort by deletion date, newest first
    usort($items, function($a, $b) {
        return $b['deleted_at'] - $a['deleted_at'];
    });

    return $items;
}

function get_dir_size($dir) {
    $size = 0;
    $it = new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS);
    foreach (new RecursiveIteratorIterator($it) as $file) {
        $size += $file->getSize();
    }
    return $size;
}

function restore_from_trash($trash_id) {
    global $TRASH_DIR, $TRASH_META_DIR, $BASE_DIR;
    $meta_file = $TRASH_META_DIR . '/' . $trash_id . '.json';
    if (!file_exists($meta_file)) return false;

    $meta = json_decode(file_get_contents($meta_file), true);
    if (!$meta) return false;

    $pattern = $TRASH_DIR . '/' . $trash_id . '_*';
    $matches = glob($pattern);
    if (empty($matches)) {
        unlink($meta_file);
        return false;
    }
    $trash_path = $matches[0];
    $restore_path = $BASE_DIR . '/' . $meta['original_path'];

    // Ensure parent dir exists
    $parent = dirname($restore_path);
    if (!is_dir($parent)) {
        mkdir($parent, 0755, true);
    }

    // If target exists, append suffix
    if (file_exists($restore_path)) {
        $info = pathinfo($restore_path);
        $i = 1;
        do {
            if (isset($info['extension'])) {
                $restore_path = $info['dirname'] . '/' . $info['filename'] . '_' . $i . '.' . $info['extension'];
            } else {
                $restore_path = $info['dirname'] . '/' . $info['filename'] . '_' . $i;
            }
            $i++;
        } while (file_exists($restore_path));
    }

    if (rename($trash_path, $restore_path)) {
        unlink($meta_file);
        return true;
    }
    return false;
}

function get_trash_path($trash_id) {
    global $TRASH_DIR;
    $pattern = $TRASH_DIR . '/' . $trash_id . '_*';
    $matches = glob($pattern);
    return empty($matches) ? false : $matches[0];
}

function safe_trash_subpath($trash_root, $subdir) {
    if ($subdir === '') return $trash_root;
    $full = realpath($trash_root . '/' . $subdir);
    if ($full === false || strpos($full, realpath($trash_root)) !== 0) {
        return false;
    }
    return $full;
}

function restore_file_from_trash($trash_id, $subpath) {
    global $TRASH_DIR, $TRASH_META_DIR, $BASE_DIR;
    $meta_file = $TRASH_META_DIR . '/' . $trash_id . '.json';
    if (!file_exists($meta_file)) return false;

    $meta = json_decode(file_get_contents($meta_file), true);
    if (!$meta) return false;

    $trash_root = get_trash_path($trash_id);
    if (!$trash_root) return false;

    $source = safe_trash_subpath($trash_root, $subpath);
    if (!$source || !file_exists($source)) return false;

    // Determine original restore location
    $original_dir = dirname($meta['original_path']);
    if ($original_dir === '.') $original_dir = '';
    $restore_path = $BASE_DIR . '/' . ($original_dir !== '' ? $original_dir . '/' : '') . $subpath;

    // Ensure parent dir exists
    $parent = dirname($restore_path);
    if (!is_dir($parent)) {
        mkdir($parent, 0755, true);
    }

    // If target exists, append suffix
    if (file_exists($restore_path)) {
        $info = pathinfo($restore_path);
        $i = 1;
        do {
            if (isset($info['extension'])) {
                $restore_path = $info['dirname'] . '/' . $info['filename'] . '_' . $i . '.' . $info['extension'];
            } else {
                $restore_path = $info['dirname'] . '/' . $info['filename'] . '_' . $i;
            }
            $i++;
        } while (file_exists($restore_path));
    }

    // Copy (not move) to preserve trash integrity
    if (is_dir($source)) {
        return copy_dir_recursive($source, $restore_path);
    } else {
        return copy($source, $restore_path);
    }
}

function copy_dir_recursive($src, $dst) {
    if (!mkdir($dst, 0755, true)) return false;
    $it = new RecursiveDirectoryIterator($src, RecursiveDirectoryIterator::SKIP_DOTS);
    $files = new RecursiveIteratorIterator($it, RecursiveIteratorIterator::SELF_FIRST);
    foreach ($files as $file) {
        $rel = substr($file->getPathname(), strlen($src) + 1);
        $target = $dst . '/' . $rel;
        if ($file->isDir()) {
            if (!is_dir($target)) mkdir($target, 0755, true);
        } else {
            copy($file->getPathname(), $target);
        }
    }
    return true;
}

function permanent_delete($trash_id) {
    global $TRASH_DIR, $TRASH_META_DIR;
    $meta_file = $TRASH_META_DIR . '/' . $trash_id . '.json';

    $pattern = $TRASH_DIR . '/' . $trash_id . '_*';
    $matches = glob($pattern);
    foreach ($matches as $path) {
        if (is_dir($path)) {
            delete_dir_recursive($path);
        } else {
            unlink($path);
        }
    }

    if (file_exists($meta_file)) unlink($meta_file);
    return true;
}

function delete_dir_recursive($dir) {
    $it = new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS);
    $files_iter = new RecursiveIteratorIterator($it, RecursiveIteratorIterator::CHILD_FIRST);
    foreach ($files_iter as $file) {
        if ($file->isDir()) {
            rmdir($file->getRealPath());
        } else {
            unlink($file->getRealPath());
        }
    }
    rmdir($dir);
}

function empty_trash() {
    global $TRASH_DIR, $TRASH_META_DIR;
    $count = 0;
    foreach (glob($TRASH_META_DIR . '/*.json') as $meta_file) {
        $trash_id = basename($meta_file, '.json');
        permanent_delete($trash_id);
        $count++;
    }
    return $count;
}

function get_trash_total_size() {
    global $TRASH_DIR;
    if (!is_dir($TRASH_DIR)) return 0;
    $size = 0;
    $it = new RecursiveDirectoryIterator($TRASH_DIR, RecursiveDirectoryIterator::SKIP_DOTS);
    foreach (new RecursiveIteratorIterator($it) as $file) {
        if (strpos($file->getPathname(), '/.meta/') !== false) continue;
        $size += $file->getSize();
    }
    return $size;
}

$message = '';
$error = '';

// Flash message from redirect
if (isset($_SESSION['flash_message'])) {
    $message = $_SESSION['flash_message'];
    unset($_SESSION['flash_message']);
}

$show_trash = isset($_GET['trash']);
$show_settings = isset($_GET['settings']);

// Current directory (relative to BASE_DIR)
$dir = isset($_GET['dir']) ? $_GET['dir'] : '';
$dir = str_replace('\\', '/', $dir);
$dir = trim($dir, '/');

// Validate directory
$current_path = $BASE_DIR;
if ($dir !== '') {
    $current_path = safe_path($BASE_DIR, $dir);
    if ($current_path === false || !is_dir($current_path)) {
        $dir = '';
        $current_path = $BASE_DIR;
        $error = __('invalid_dir');
    }
}

// Handle actions
if ($_SERVER['REQUEST_METHOD'] === 'POST' && is_logged_in()) {
    $action = isset($_POST['action']) ? $_POST['action'] : '';
    if ($action !== 'login') {
        check_csrf();
    }
    
    switch ($action) {
        case 'delete':
            $target = isset($_POST['target']) ? $_POST['target'] : '';
            $full_path = safe_path($BASE_DIR, $target);
            if ($full_path === false) {
                $error = __('invalid_path');
            } elseif (is_dir($full_path) || is_file($full_path)) {
                if (move_to_trash($full_path, $target)) {
                    $message = __('moved_to_trash') . ': ' . htmlspecialchars(basename($full_path));
                } else {
                    $error = __('failed_move_to_trash');
                }
            } else {
                $error = __('target_not_found');
            }
            break;
            
        case 'trash_restore':
            $trash_id = isset($_POST['trash_id']) ? $_POST['trash_id'] : '';
            if (preg_match('/^trash_[a-f0-9.]+$/', $trash_id) && restore_from_trash($trash_id)) {
                $message = __('restored_from_trash');
            } else {
                $error = __('failed_restore');
            }
            $show_trash = true;
            break;
            
        case 'trash_delete':
            $trash_id = isset($_POST['trash_id']) ? $_POST['trash_id'] : '';
            if (preg_match('/^trash_[a-f0-9.]+$/', $trash_id) && permanent_delete($trash_id)) {
                $message = __('permanently_deleted');
            } else {
                $error = __('failed_permanent_delete');
            }
            $show_trash = true;
            break;
            
        case 'trash_empty':
            $count = empty_trash();
            $message = __('trash_emptied') . ' (' . $count . ')';
            $show_trash = true;
            break;
            
        case 'trash_restore_file':
            $trash_id = isset($_POST['trash_id']) ? $_POST['trash_id'] : '';
            $subpath = isset($_POST['subpath']) ? $_POST['subpath'] : '';
            if (preg_match('/^trash_[a-f0-9.]+$/', $trash_id) && $subpath !== '' && restore_file_from_trash($trash_id, $subpath)) {
                $message = __('restored_from_trash') . ': ' . htmlspecialchars(basename($subpath));
            } else {
                $error = __('failed_restore');
            }
            $show_trash = true;
            break;
            
        case 'upload':
            if (isset($_FILES['files'])) {
                $uploaded = 0;
                $failed = 0;
                $upload_dir = $current_path;
                
                foreach ($_FILES['files']['name'] as $i => $name) {
                    if ($_FILES['files']['error'][$i] === UPLOAD_ERR_OK) {
                        $safe_name = basename($name);
                        $dest = $upload_dir . '/' . $safe_name;
                        if (move_uploaded_file($_FILES['files']['tmp_name'][$i], $dest)) {
                            chmod($dest, 0644);
                            $uploaded++;
                        } else {
                            $failed++;
                        }
                    } else {
                        $failed++;
                    }
                }
                $message = __('uploaded') . ': ' . $uploaded;
                if ($failed > 0) $error = __('upload_failed') . ': ' . $failed;
            }
            break;
            
        case 'mkdir':
            $dirname = isset($_POST['dirname']) ? trim($_POST['dirname']) : '';
            $dirname = basename($dirname);
            if ($dirname === '' || $dirname === '.' || $dirname === '..') {
                $error = __('invalid_dir_name');
            } else {
                $new_dir = $current_path . '/' . $dirname;
                if (file_exists($new_dir)) {
                    $error = __('already_exists');
                } elseif (mkdir($new_dir, 0755)) {
                    $message = __('dir_created') . ': ' . htmlspecialchars($dirname);
                } else {
                    $error = __('failed_create_dir');
                }
            }
            break;
            
        case 'save_settings':
            $new_lang = isset($_POST['lang']) ? $_POST['lang'] : '';
            if (array_key_exists($new_lang, $AVAILABLE_LANGS)) {
                $settings['lang'] = $new_lang;
            }
            
            $new_tz = isset($_POST['timezone']) ? $_POST['timezone'] : '';
            if (in_array($new_tz, timezone_identifiers_list())) {
                $settings['timezone'] = $new_tz;
            }
            
            $new_days = isset($_POST['retention_days']) ? intval($_POST['retention_days']) : 30;
            if ($new_days < 1) $new_days = 1;
            if ($new_days > 365) $new_days = 365;
            $settings['retention_days'] = $new_days;
            file_put_contents($RETENTION_FILE, $new_days);
            
            $new_pw = isset($_POST['new_password']) ? $_POST['new_password'] : '';
            if (!empty($new_pw)) {
                $current_pw = isset($_POST['current_password']) ? $_POST['current_password'] : '';
                $confirm_pw = isset($_POST['confirm_password']) ? $_POST['confirm_password'] : '';
                
                if (!verify_password($current_pw)) {
                    $error = __('wrong_current_password');
                } elseif (strlen($new_pw) < 4) {
                    $error = __('password_too_short');
                } elseif ($new_pw !== $confirm_pw) {
                    $error = __('passwords_mismatch');
                } else {
                    file_put_contents($PASSWORD_FILE, password_hash($new_pw, PASSWORD_DEFAULT));
                    $message = __('settings_saved_pw');
                }
            } else {
                if (!$error) {
                    $message = __('settings_saved');
                }
            }
            
            if (!$error) {
                file_put_contents($SETTINGS_FILE, json_encode($settings, JSON_PRETTY_PRINT));
                $_SESSION['flash_message'] = $message;
                header("Location: admin.php?settings=1");
                exit;
            }
            $show_settings = true;
            break;
    }
}

// Read directory contents
$items = [];
$hidden_items = ['admin.php', '.admin_password', '.lang', '.trash', '.settings.json'];
if (is_dir($current_path)) {
    $scan = scandir($current_path);
    foreach ($scan as $item) {
        if ($item === '.' || $item === '..') continue;
        if (in_array($item, $hidden_items)) continue;
        $item_path = $current_path . '/' . $item;
        $rel_path = ($dir !== '' ? $dir . '/' : '') . $item;
        $items[] = [
            'name' => $item,
            'path' => $rel_path,
            'is_dir' => is_dir($item_path),
            'size' => is_file($item_path) ? filesize($item_path) : 0,
            'mtime' => filemtime($item_path),
        ];
    }
}

usort($items, function($a, $b) {
    if ($a['is_dir'] !== $b['is_dir']) return $b['is_dir'] - $a['is_dir'];
    return strcasecmp($a['name'], $b['name']);
});

// Disk space info
$disk_total = disk_total_space($BASE_DIR);
$disk_free = disk_free_space($BASE_DIR);
$disk_used = $disk_total - $disk_free;
$disk_percent = $disk_total > 0 ? round(($disk_used / $disk_total) * 100, 1) : 0;

// Trash info
$trash_items = get_trash_items();
$trash_count = count($trash_items);
$trash_size = get_trash_total_size();

// Trash browse mode (viewing inside a deleted folder)
$browse_trash_id = isset($_GET['browse']) ? $_GET['browse'] : '';
$browse_subdir = isset($_GET['subdir']) ? $_GET['subdir'] : '';
$browse_subdir = trim(str_replace('\\', '/', $browse_subdir), '/');
$browse_items = [];
$browse_trash_name = '';
$browse_trash_meta = null;

if ($show_trash && $browse_trash_id !== '' && preg_match('/^trash_[a-f0-9.]+$/', $browse_trash_id)) {
    $browse_root = get_trash_path($browse_trash_id);
    if ($browse_root && is_dir($browse_root)) {
        $browse_current = safe_trash_subpath($browse_root, $browse_subdir);
        if ($browse_current && is_dir($browse_current)) {
            $browse_trash_name = basename($browse_root);
            // Remove trash_id prefix from name
            $prefix = $browse_trash_id . '_';
            if (strpos($browse_trash_name, $prefix) === 0) {
                $browse_trash_name = substr($browse_trash_name, strlen($prefix));
            }
            // Load meta
            $meta_file = $TRASH_META_DIR . '/' . $browse_trash_id . '.json';
            if (file_exists($meta_file)) {
                $browse_trash_meta = json_decode(file_get_contents($meta_file), true);
            }
            // Scan directory
            $scan = scandir($browse_current);
            foreach ($scan as $entry) {
                if ($entry === '.' || $entry === '..') continue;
                $entry_full = $browse_current . '/' . $entry;
                $entry_rel = ($browse_subdir !== '' ? $browse_subdir . '/' : '') . $entry;
                $browse_items[] = [
                    'name' => $entry,
                    'subpath' => $entry_rel,
                    'is_dir' => is_dir($entry_full),
                    'size' => is_file($entry_full) ? filesize($entry_full) : get_dir_size($entry_full),
                    'mtime' => filemtime($entry_full),
                ];
            }
            usort($browse_items, function($a, $b) {
                if ($a['is_dir'] !== $b['is_dir']) return $b['is_dir'] - $a['is_dir'];
                return strcasecmp($a['name'], $b['name']);
            });
        } else {
            $browse_trash_id = '';
            $error = __('invalid_path');
        }
    } else {
        $browse_trash_id = '';
    }
}

// Breadcrumb
$breadcrumbs = [['name' => __('breadcrumb_root'), 'path' => '']];
if ($dir !== '') {
    $parts = explode('/', $dir);
    $accumulated = '';
    foreach ($parts as $part) {
        $accumulated .= ($accumulated !== '' ? '/' : '') . $part;
        $breadcrumbs[] = ['name' => $part, 'path' => $accumulated];
    }
}

// Build lang switch URL
function lang_switch_url($lang) {
    $params = $_GET;
    $params['lang'] = $lang;
    return '?' . http_build_query($params);
}

// ---- LOGIN PAGE ----
function show_login_page($error = '') {
    global $AVAILABLE_LANGS, $current_lang;
?>
<!DOCTYPE html>
<html lang="<?= $current_lang ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= __('login_title') ?></title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; color: #333; display: flex; justify-content: center; align-items: center; min-height: 100vh; }
        .login-box { background: white; padding: 40px; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); width: 360px; }
        .login-box h1 { text-align: center; color: #2196F3; margin-bottom: 25px; font-size: 1.5em; }
        .login-box input[type="password"] { width: 100%; padding: 12px 16px; border: 1px solid #ddd; border-radius: 6px; font-size: 1em; margin-bottom: 15px; }
        .login-box input[type="password"]:focus { outline: none; border-color: #2196F3; box-shadow: 0 0 0 2px rgba(33,150,243,0.2); }
        .login-box button { width: 100%; padding: 12px; background: #2196F3; color: white; border: none; border-radius: 6px; font-size: 1em; cursor: pointer; }
        .login-box button:hover { background: #1976D2; }
        .error { color: #c62828; text-align: center; margin-bottom: 15px; font-size: 0.9em; }
        .lang-bar { text-align: center; margin-top: 15px; }
        .lang-bar a { color: #666; text-decoration: none; margin: 0 5px; font-size: 0.85em; padding: 3px 8px; border-radius: 3px; }
        .lang-bar a.active { background: #2196F3; color: white; }
        .lang-bar a:hover { opacity: 0.8; }
    </style>
</head>
<body>
    <div class="login-box">
        <h1>&#128274; <?= __('login_title') ?></h1>
        <?php if ($error): ?>
            <div class="error"><?= htmlspecialchars($error) ?></div>
        <?php endif; ?>
        <form method="post">
            <input type="hidden" name="action" value="login">
            <input type="password" name="password" placeholder="<?= __('password_placeholder') ?>" autofocus required>
            <button type="submit"><?= __('login_btn') ?></button>
        </form>
        <div class="lang-bar">
            <?php foreach ($AVAILABLE_LANGS as $code => $label): ?>
                <a href="<?= lang_switch_url($code) ?>" class="<?= $code === $current_lang ? 'active' : '' ?>"><?= $label ?></a>
            <?php endforeach; ?>
        </div>
    </div>
</body>
</html>
<?php
}
?>
<!DOCTYPE html>
<html lang="<?= $current_lang ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= __('title') ?></title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; color: #333; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        
        .header { background: #2196F3; color: white; padding: 15px 20px; border-radius: 8px 8px 0 0; display: flex; justify-content: space-between; align-items: center; }
        .header h1 { font-size: 1.4em; }
        .header-links { display: flex; gap: 15px; align-items: center; }
        .header a { color: white; text-decoration: none; opacity: 0.8; font-size: 0.9em; }
        .header a:hover { opacity: 1; }
        
        .breadcrumb { background: #e3f2fd; padding: 10px 20px; border-bottom: 1px solid #bbdefb; }
        .breadcrumb a { color: #1565C0; text-decoration: none; }
        .breadcrumb a:hover { text-decoration: underline; }
        .breadcrumb span { color: #666; margin: 0 5px; }
        
        .toolbar { background: white; padding: 15px 20px; border-bottom: 1px solid #ddd; display: flex; gap: 15px; flex-wrap: wrap; align-items: center; }
        
        .msg { padding: 10px 20px; }
        .msg.success { background: #e8f5e9; color: #2e7d32; }
        .msg.error { background: #ffebee; color: #c62828; }
        
        .file-list { background: white; border-radius: 0 0 8px 8px; overflow: hidden; }
        .file-list table { width: 100%; border-collapse: collapse; }
        .file-list th { background: #fafafa; text-align: left; padding: 10px 15px; border-bottom: 2px solid #eee; font-weight: 600; font-size: 0.85em; color: #666; text-transform: uppercase; }
        .file-list td { padding: 10px 15px; border-bottom: 1px solid #f0f0f0; }
        .file-list tr:hover { background: #f8f9fa; }
        .file-list tr:last-child td { border-bottom: none; }
        
        .icon { margin-right: 8px; font-size: 1.1em; }
        .file-link { color: #1565C0; text-decoration: none; }
        .file-link:hover { text-decoration: underline; }
        
        .btn { display: inline-block; padding: 6px 14px; border: none; border-radius: 4px; cursor: pointer; font-size: 0.9em; text-decoration: none; }
        .btn-primary { background: #2196F3; color: white; }
        .btn-primary:hover { background: #1976D2; }
        .btn-danger { background: #f44336; color: white; }
        .btn-danger:hover { background: #d32f2f; }
        .btn-success { background: #4CAF50; color: white; }
        .btn-success:hover { background: #388E3C; }
        .btn-warning { background: #FF9800; color: white; }
        .btn-warning:hover { background: #F57C00; }
        .btn-sm { padding: 4px 10px; font-size: 0.8em; }
        
        input[type="text"], input[type="password"] { padding: 6px 12px; border: 1px solid #ddd; border-radius: 4px; font-size: 0.9em; }
        input[type="file"] { font-size: 0.9em; }
        
        .upload-form { display: flex; gap: 10px; align-items: center; }
        .mkdir-form { display: flex; gap: 10px; align-items: center; }
        
        .empty { text-align: center; padding: 40px; color: #999; }
        
        .confirm-dialog { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); z-index: 100; align-items: center; justify-content: center; }
        .confirm-dialog.active { display: flex; }
        .confirm-box { background: white; padding: 25px; border-radius: 8px; max-width: 400px; text-align: center; }
        .confirm-box p { margin-bottom: 20px; }
        .confirm-box .actions { display: flex; gap: 10px; justify-content: center; }
        
        .settings-header { background: #607D8B; }
        .settings-page { padding: 20px; max-width: 600px; margin: 0 auto; }
        .settings-form fieldset { border: 1px solid #ddd; border-radius: 8px; padding: 15px 20px; margin-bottom: 20px; background: white; }
        .settings-form legend { font-weight: 600; font-size: 1em; padding: 0 8px; color: #333; }
        .settings-row { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
        .settings-row label { min-width: 160px; font-size: 0.9em; font-weight: 600; color: #555; }
        .settings-row input, .settings-row select { padding: 6px 10px; border: 1px solid #ccc; border-radius: 4px; font-size: 0.9em; }
        .settings-hint { font-size: 0.8em; color: #999; }
        .settings-actions { text-align: center; margin-top: 20px; }
        .settings-actions .btn { margin: 0 5px; }
        
        .size { color: #666; font-size: 0.9em; }
        .date { color: #999; font-size: 0.85em; }
        
        .disk-info { background: white; padding: 12px 20px; border-bottom: 1px solid #ddd; display: flex; align-items: center; gap: 15px; font-size: 0.85em; color: #555; }
        .disk-bar { flex: 1; max-width: 300px; height: 16px; background: #e0e0e0; border-radius: 8px; overflow: hidden; position: relative; }
        .disk-bar-fill { height: 100%; border-radius: 8px; transition: width 0.3s ease; }
        .disk-bar-fill.ok { background: linear-gradient(90deg, #4CAF50, #66BB6A); }
        .disk-bar-fill.warn { background: linear-gradient(90deg, #FF9800, #FFA726); }
        .disk-bar-fill.critical { background: linear-gradient(90deg, #f44336, #EF5350); }
        .disk-bar-text { position: absolute; top: 0; left: 0; right: 0; bottom: 0; display: flex; align-items: center; justify-content: center; font-size: 0.75em; font-weight: 600; color: #333; }
        .disk-label { white-space: nowrap; }
        
        .trash-link { display: inline-flex; align-items: center; gap: 5px; }
        .trash-badge { background: #f44336; color: white; padding: 1px 6px; border-radius: 10px; font-size: 0.75em; font-weight: 600; }
        .trash-header { background: #FF9800; }
        .trash-info { background: #fff3e0; padding: 10px 20px; border-bottom: 1px solid #ffe0b2; font-size: 0.85em; color: #e65100; display: flex; justify-content: space-between; align-items: center; }
        .original-path { color: #999; font-size: 0.8em; }
        
        @media (max-width: 768px) {
            .toolbar { flex-direction: column; align-items: flex-start; }
            .file-list { overflow-x: auto; }
        }
    </style>
</head>
<body>
<div class="container">
    <?php
        $header_class = '';
        if ($show_trash) $header_class = 'trash-header';
        if ($show_settings) $header_class = 'settings-header';
    ?>
    <div class="header <?= $header_class ?>">
        <h1><?php
            if ($show_settings) echo '&#9881; ' . __('settings_title');
            elseif ($show_trash) echo '&#128465; ' . __('trash_title');
            else echo __('title');
        ?></h1>
        <div class="header-links">
            <?php if ($show_trash || $show_settings): ?>
                <a href="?">&#8592; <?= __('back_to_files') ?></a>
            <?php else: ?>
                <a href="?trash=1" class="trash-link">&#128465; <?= __('trash') ?><?php if ($trash_count > 0): ?> <span class="trash-badge"><?= $trash_count ?></span><?php endif; ?></a>
                <a href="/">&#8592; <?= __('back_to_files') ?></a>
            <?php endif; ?>
            <a href="?settings=1">&#9881; <?= __('settings_title') ?></a>
            <a href="?logout=1">&#10140; <?= __('logout') ?></a>
        </div>
    </div>
    
    <?php if ($show_settings): ?>
    <!-- SETTINGS VIEW -->
    <?php if ($message): ?>
        <div class="msg success"><?= $message ?></div>
    <?php endif; ?>
    <?php if ($error): ?>
        <div class="msg error"><?= $error ?></div>
    <?php endif; ?>
    
    <div class="settings-page">
        <form method="post" class="settings-form">
            <input type="hidden" name="action" value="save_settings">
            <input type="hidden" name="csrf" value="<?= $csrf ?>">
            
            <fieldset>
                <legend>&#127760; <?= __('general_settings') ?></legend>
                
                <div class="settings-row">
                    <label for="s_lang"><?= __('language') ?></label>
                    <select name="lang" id="s_lang">
                        <?php foreach ($AVAILABLE_LANGS as $code => $label): ?>
                            <option value="<?= $code ?>" <?= $code === $current_lang ? 'selected' : '' ?>><?= $label ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                
                <div class="settings-row" style="flex-wrap:wrap">
                    <label for="s_tz_search"><?= __('timezone') ?></label>
                    <div style="display:flex;flex-direction:column;gap:4px">
                        <input type="text" id="s_tz_search" placeholder="<?= __('tz_search_placeholder') ?>" style="width:280px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.9em" autocomplete="off">
                        <select name="timezone" id="s_tz" size="8" style="width:280px">
                            <?php
                            $tz_groups = [];
                            foreach (timezone_identifiers_list() as $tz_id) {
                                $parts = explode('/', $tz_id, 2);
                                if (count($parts) === 2) {
                                    $tz_groups[$parts[0]][] = $tz_id;
                                }
                            }
                            foreach ($tz_groups as $region => $zones):
                            ?>
                            <optgroup label="<?= $region ?>">
                                <?php foreach ($zones as $tz_id): ?>
                                    <option value="<?= $tz_id ?>" <?= $tz_id === $server_tz ? 'selected' : '' ?>><?= str_replace('_', ' ', explode('/', $tz_id, 2)[1]) ?></option>
                                <?php endforeach; ?>
                            </optgroup>
                            <?php endforeach; ?>
                        </select>
                    </div>
                </div>
            </fieldset>
            
            <fieldset>
                <legend>&#128465; <?= __('trash_settings_section') ?></legend>
                
                <div class="settings-row">
                    <label for="s_ret"><?= __('trash_retention') ?></label>
                    <input type="number" name="retention_days" id="s_ret" value="<?= $TRASH_RETENTION_DAYS ?>" min="1" max="365" style="width:80px">
                    <span><?= __('days') ?></span>
                </div>
            </fieldset>
            
            <fieldset>
                <legend>&#128274; <?= __('security_settings') ?></legend>
                <p class="settings-hint" style="margin-bottom:10px"><?= __('password_hint') ?></p>
                
                <div class="settings-row">
                    <label for="s_curpw"><?= __('current_password') ?></label>
                    <input type="password" name="current_password" id="s_curpw" autocomplete="current-password">
                </div>
                
                <div class="settings-row">
                    <label for="s_newpw"><?= __('new_password') ?></label>
                    <input type="password" name="new_password" id="s_newpw" minlength="4" autocomplete="new-password">
                </div>
                
                <div class="settings-row">
                    <label for="s_cfmpw"><?= __('confirm_new_password') ?></label>
                    <input type="password" name="confirm_password" id="s_cfmpw" minlength="4" autocomplete="new-password">
                </div>
            </fieldset>
            
            <div class="settings-actions">
                <button type="submit" class="btn btn-primary"><?= __('save_btn') ?></button>
                <a href="?" class="btn"><?= __('cancel_btn') ?></a>
            </div>
        </form>
    </div>
    
    <?php elseif ($show_trash): ?>
    <!-- TRASH VIEW -->
    <div class="trash-info">
        <span><?= __('trash_size') ?>: <?= format_size($trash_size) ?> &middot; <?= __('trash_retention') ?>: <?= $TRASH_RETENTION_DAYS ?> <?= __('days') ?></span>
        <?php if ($trash_count > 0): ?>
        <form method="post" style="display:inline" onsubmit="return confirm('<?= __('confirm_empty_trash') ?>')">
            <input type="hidden" name="action" value="trash_empty">
            <input type="hidden" name="csrf" value="<?= $csrf ?>">
            <button type="submit" class="btn btn-danger btn-sm"><?= __('empty_trash_btn') ?></button>
        </form>
        <?php endif; ?>
    </div>
    
    <?php if ($message): ?>
        <div class="msg success"><?= $message ?></div>
    <?php endif; ?>
    <?php if ($error): ?>
        <div class="msg error"><?= $error ?></div>
    <?php endif; ?>
    
    <div class="file-list">
        <?php if ($browse_trash_id !== ''): ?>
        <!-- BROWSE INSIDE TRASH FOLDER -->
        <div class="breadcrumb">
            <a href="?trash=1">&#128465; <?= __('trash') ?></a>
            <span>/</span>
            <?php if ($browse_subdir === ''): ?>
                <strong><?= htmlspecialchars($browse_trash_name) ?></strong>
            <?php else: ?>
                <a href="?trash=1&browse=<?= urlencode($browse_trash_id) ?>"><?= htmlspecialchars($browse_trash_name) ?></a>
                <?php
                    $sub_parts = explode('/', $browse_subdir);
                    $sub_acc = '';
                    foreach ($sub_parts as $si => $sp) {
                        $sub_acc .= ($sub_acc !== '' ? '/' : '') . $sp;
                        echo '<span>/</span>';
                        if ($si === count($sub_parts) - 1) {
                            echo '<strong>' . htmlspecialchars($sp) . '</strong>';
                        } else {
                            echo '<a href="?trash=1&browse=' . urlencode($browse_trash_id) . '&subdir=' . urlencode($sub_acc) . '">' . htmlspecialchars($sp) . '</a>';
                        }
                    }
                ?>
            <?php endif; ?>
        </div>
        <?php if ($browse_trash_meta): ?>
            <div style="padding:5px 20px; font-size:0.8em; color:#999;">
                <?= __('col_original_path') ?>: <?= htmlspecialchars($browse_trash_meta['original_path']) ?>
                | <?= __('col_deleted') ?>: <?= date('Y-m-d H:i', $browse_trash_meta['deleted_at']) ?>
            </div>
        <?php endif; ?>
        <?php if (empty($browse_items)): ?>
            <div class="empty"><?= __('dir_empty') ?></div>
        <?php else: ?>
            <table>
                <thead>
                    <tr>
                        <th><?= __('col_name') ?></th>
                        <th><?= __('col_size') ?></th>
                        <th><?= __('col_created') ?></th>
                        <th><?= __('col_deleted') ?></th>
                        <th><?= __('col_actions') ?></th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($browse_items as $bitem): ?>
                        <tr>
                            <td>
                                <span class="icon"><?= $bitem['is_dir'] ? '&#128194;' : '&#128196;' ?></span>
                                <?php if ($bitem['is_dir']): ?>
                                    <a href="?trash=1&browse=<?= urlencode($browse_trash_id) ?>&subdir=<?= urlencode($bitem['subpath']) ?>"><?= htmlspecialchars($bitem['name']) ?></a>
                                <?php else: ?>
                                    <?= htmlspecialchars($bitem['name']) ?>
                                <?php endif; ?>
                            </td>
                            <td class="size"><?= format_size($bitem['size']) ?></td>
                            <td class="date"><?= date('Y-m-d H:i', $bitem['mtime']) ?></td>
                            <td class="date"><?= date('Y-m-d H:i', $browse_trash_meta['deleted_at']) ?></td>
                            <td>
                                <form method="post" style="display:inline">
                                    <input type="hidden" name="action" value="trash_restore_file">
                                    <input type="hidden" name="trash_id" value="<?= htmlspecialchars($browse_trash_id) ?>">
                                    <input type="hidden" name="subpath" value="<?= htmlspecialchars($bitem['subpath']) ?>">
                                    <input type="hidden" name="csrf" value="<?= $csrf ?>">
                                    <button type="submit" class="btn btn-success btn-sm"><?= __('restore_btn') ?></button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        <?php endif; ?>
        
        <?php else: ?>
        <!-- TRASH LIST -->
        <?php if (empty($trash_items)): ?>
            <div class="empty"><?= __('trash_empty') ?></div>
        <?php else: ?>
            <table>
                <thead>
                    <tr>
                        <th><?= __('col_name') ?></th>
                        <th><?= __('col_original_path') ?></th>
                        <th><?= __('col_size') ?></th>
                        <th><?= __('col_created') ?></th>
                        <th><?= __('col_deleted') ?></th>
                        <th><?= __('col_actions') ?></th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($trash_items as $item): ?>
                        <?php
                            $days_left = $TRASH_RETENTION_DAYS - floor((time() - $item['deleted_at']) / 86400);
                            if ($days_left < 0) $days_left = 0;
                        ?>
                        <tr>
                            <td>
                                <span class="icon"><?= $item['is_dir'] ? '&#128194;' : '&#128196;' ?></span>
                                <?php if ($item['is_dir']): ?>
                                    <a href="?trash=1&browse=<?= urlencode($item['id']) ?>"><?= htmlspecialchars($item['name']) ?></a>
                                <?php else: ?>
                                    <?= htmlspecialchars($item['name']) ?>
                                <?php endif; ?>
                            </td>
                            <td class="original-path"><?= htmlspecialchars($item['original_path']) ?></td>
                            <td class="size"><?= format_size($item['size']) ?></td>
                            <td class="date" title="<?= __('col_created') ?>">
                                <?php if ($item['mtime'] > 0): ?>
                                    <?= date('Y-m-d H:i', $item['mtime']) ?>
                                <?php else: ?>
                                    -
                                <?php endif; ?>
                            </td>
                            <td class="date" title="<?= __('col_deleted') ?>">
                                <?= date('Y-m-d H:i', $item['deleted_at']) ?>
                                <br><small><?= $days_left ?> <?= __('days_left') ?></small>
                            </td>
                            <td>
                                <?php if ($item['is_dir']): ?>
                                <a href="?trash=1&browse=<?= urlencode($item['id']) ?>" class="btn btn-primary btn-sm">&#128270; <?= __('browse_btn') ?></a>
                                <?php endif; ?>
                                <form method="post" style="display:inline">
                                    <input type="hidden" name="action" value="trash_restore">
                                    <input type="hidden" name="trash_id" value="<?= htmlspecialchars($item['id']) ?>">
                                    <input type="hidden" name="csrf" value="<?= $csrf ?>">
                                    <button type="submit" class="btn btn-success btn-sm"><?= __('restore_btn') ?></button>
                                </form>
                                <form method="post" style="display:inline" onsubmit="return confirm('<?= __('confirm_permanent_delete') ?>')">
                                    <input type="hidden" name="action" value="trash_delete">
                                    <input type="hidden" name="trash_id" value="<?= htmlspecialchars($item['id']) ?>">
                                    <input type="hidden" name="csrf" value="<?= $csrf ?>">
                                    <button type="submit" class="btn btn-danger btn-sm"><?= __('delete_forever_btn') ?></button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        <?php endif; ?>
        <?php endif; ?>
    </div>
    
    <?php else: ?>
    <!-- FILES VIEW -->
    <div class="breadcrumb">
        <?php foreach ($breadcrumbs as $i => $bc): ?>
            <?php if ($i > 0): ?><span>/</span><?php endif; ?>
            <?php if ($i === count($breadcrumbs) - 1): ?>
                <strong><?= htmlspecialchars($bc['name']) ?></strong>
            <?php else: ?>
                <a href="?dir=<?= urlencode($bc['path']) ?>"><?= htmlspecialchars($bc['name']) ?></a>
            <?php endif; ?>
        <?php endforeach; ?>
    </div>
    
    <div class="toolbar">
        <form class="upload-form" method="post" enctype="multipart/form-data">
            <input type="hidden" name="action" value="upload">
            <input type="hidden" name="csrf" value="<?= $csrf ?>">
            <input type="file" name="files[]" multiple required>
            <button type="submit" class="btn btn-primary"><?= __('upload_btn') ?></button>
        </form>
        
        <form class="mkdir-form" method="post">
            <input type="hidden" name="action" value="mkdir">
            <input type="hidden" name="csrf" value="<?= $csrf ?>">
            <input type="text" name="dirname" placeholder="<?= __('new_folder_placeholder') ?>" required>
            <button type="submit" class="btn btn-success"><?= __('create_folder_btn') ?></button>
        </form>
    </div>
    
    <div class="disk-info">
        <span class="disk-label"><?= __('disk_space') ?>:</span>
        <div class="disk-bar">
            <div class="disk-bar-fill <?= $disk_percent >= 90 ? 'critical' : ($disk_percent >= 70 ? 'warn' : 'ok') ?>" style="width: <?= $disk_percent ?>%"></div>
            <div class="disk-bar-text"><?= $disk_percent ?>%</div>
        </div>
        <span class="disk-label"><?= format_size($disk_used) ?> / <?= format_size($disk_total) ?> (<?= __('disk_free') ?>: <?= format_size($disk_free) ?>)</span>
        <?php if ($trash_count > 0): ?>
            <span class="disk-label">| &#128465; <?= __('trash') ?>: <?= format_size($trash_size) ?></span>
        <?php endif; ?>
    </div>
    
    <?php if ($message): ?>
        <div class="msg success"><?= $message ?></div>
    <?php endif; ?>
    <?php if ($error): ?>
        <div class="msg error"><?= $error ?></div>
    <?php endif; ?>
    
    <div class="file-list">
        <?php if (empty($items) && $dir === ''): ?>
            <div class="empty"><?= __('no_files') ?></div>
        <?php else: ?>
            <table>
                <thead>
                    <tr>
                        <th><?= __('col_name') ?></th>
                        <th><?= __('col_size') ?></th>
                        <th><?= __('col_modified') ?></th>
                        <th><?= __('col_actions') ?></th>
                    </tr>
                </thead>
                <tbody>
                    <?php if ($dir !== ''): ?>
                        <?php
                            $parent = dirname($dir);
                            if ($parent === '.') $parent = '';
                        ?>
                        <tr>
                            <td colspan="4">
                                <span class="icon">&#128194;</span>
                                <a class="file-link" href="?dir=<?= urlencode($parent) ?>">..</a>
                            </td>
                        </tr>
                    <?php endif; ?>
                    
                    <?php foreach ($items as $item): ?>
                        <tr>
                            <td>
                                <?php if ($item['is_dir']): ?>
                                    <span class="icon">&#128194;</span>
                                    <a class="file-link" href="?dir=<?= urlencode($item['path']) ?>"><?= htmlspecialchars($item['name']) ?></a>
                                <?php else: ?>
                                    <span class="icon">&#128196;</span>
                                    <a class="file-link" href="/<?= rawurlencode($item['path']) ?>" target="_blank"><?= htmlspecialchars($item['name']) ?></a>
                                <?php endif; ?>
                            </td>
                            <td class="size"><?= $item['is_dir'] ? '-' : format_size($item['size']) ?></td>
                            <td class="date"><?= date('Y-m-d H:i', $item['mtime']) ?></td>
                            <td>
                                <?php if (!$item['is_dir']): ?>
                                    <a href="/<?= rawurlencode($item['path']) ?>" class="btn btn-primary btn-sm" download><?= __('download_btn') ?></a>
                                <?php endif; ?>
                                <button class="btn btn-danger btn-sm" onclick="confirmDelete('<?= htmlspecialchars($item['path'], ENT_QUOTES) ?>', '<?= htmlspecialchars($item['name'], ENT_QUOTES) ?>', <?= $item['is_dir'] ? 'true' : 'false' ?>)"><?= __('delete_btn') ?></button>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                    
                    <?php if (empty($items)): ?>
                        <tr><td colspan="4" class="empty"><?= __('empty_dir') ?></td></tr>
                    <?php endif; ?>
                </tbody>
            </table>
        <?php endif; ?>
    </div>
    <?php endif; ?>
</div>

<!-- Delete confirmation -->
<div class="confirm-dialog" id="confirmDialog">
    <div class="confirm-box">
        <p id="confirmText"></p>
        <div class="actions">
            <form method="post" id="deleteForm">
                <input type="hidden" name="action" value="delete">
                <input type="hidden" name="csrf" value="<?= $csrf ?>">
                <input type="hidden" name="target" id="deleteTarget">
                <button type="submit" class="btn btn-danger"><?= __('delete_btn') ?></button>
            </form>
            <button class="btn" onclick="closeDialog()"><?= __('cancel_btn') ?></button>
        </div>
    </div>
</div>


<script>
var LANG = {
    confirm_delete_file: <?= json_encode(__('confirm_delete_file')) ?>,
    confirm_delete_dir: <?= json_encode(__('confirm_delete_dir')) ?>
};
function confirmDelete(path, name, isDir) {
    var type = isDir ? LANG.confirm_delete_dir : LANG.confirm_delete_file;
    document.getElementById('confirmText').textContent = type + ' "' + name + '"?';
    document.getElementById('deleteTarget').value = path;
    document.getElementById('confirmDialog').classList.add('active');
}
function closeDialog() {
    document.getElementById('confirmDialog').classList.remove('active');
}
document.getElementById('confirmDialog').addEventListener('click', function(e) {
    if (e.target === this) closeDialog();
});

// Timezone search filter
var tzSearch = document.getElementById('s_tz_search');
var tzSelect = document.getElementById('s_tz');
if (tzSearch && tzSelect) {
    var tzOptions = [];
    var groups = tzSelect.querySelectorAll('optgroup');
    groups.forEach(function(g) {
        var opts = [];
        g.querySelectorAll('option').forEach(function(o) {
            opts.push({value: o.value, text: o.textContent, selected: o.selected});
        });
        tzOptions.push({label: g.label, options: opts});
    });
    tzSelect.addEventListener('change', function() {
        var val = this.value;
        tzOptions.forEach(function(grp) {
            grp.options.forEach(function(o) {
                o.selected = (o.value === val);
            });
        });
    });
    tzSearch.addEventListener('input', function() {
        var q = this.value.toLowerCase();
        while (tzSelect.firstChild) tzSelect.removeChild(tzSelect.firstChild);
        tzOptions.forEach(function(grp) {
            var matched = grp.options.filter(function(o) {
                return o.value.toLowerCase().indexOf(q) !== -1 || o.text.toLowerCase().indexOf(q) !== -1 || grp.label.toLowerCase().indexOf(q) !== -1 && q.length > 0;
            });
            if (matched.length === 0 && q.length > 0) return;
            if (q.length === 0) matched = grp.options;
            var og = document.createElement('optgroup');
            og.label = grp.label;
            matched.forEach(function(o) {
                var opt = document.createElement('option');
                opt.value = o.value;
                opt.textContent = o.text;
                opt.selected = o.selected;
                og.appendChild(opt);
            });
            tzSelect.appendChild(og);
        });
    });
}
</script>
</body>
</html>
