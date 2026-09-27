<?php

// Waits for MySQL, then prints the install state on stdout:
//   "fresh"       no Invoice Ninja account yet (first boot)
//   "initialized" an account exists
// Exits 1 if MySQL is still unreachable after DB_WAIT_TIMEOUT seconds.
//
// On a fresh Railway project MySQL often starts after the app, and upstream
// init.sh runs migrations immediately and exits on failure.

$host = getenv('DB_HOST') ?: '';
$port = getenv('DB_PORT') ?: '3306';
$name = getenv('DB_DATABASE') ?: '';
$user = getenv('DB_USERNAME') ?: '';
$pass = getenv('DB_PASSWORD') ?: '';
$timeout = (int) (getenv('DB_WAIT_TIMEOUT') ?: 180);

$deadline = time() + $timeout;
$dsn = "mysql:host={$host};port={$port};dbname={$name}";

while (true) {
    try {
        $pdo = new PDO($dsn, $user, $pass, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_TIMEOUT => 5,
        ]);
        break;
    } catch (PDOException $e) {
        if (time() >= $deadline) {
            fwrite(STDERR, "[railway] MySQL at {$host}:{$port} still unreachable after {$timeout}s: {$e->getMessage()}\n");
            exit(1);
        }
        fwrite(STDERR, "[railway] waiting for MySQL at {$host}:{$port} ({$e->getMessage()})\n");
        sleep(3);
    }
}

$hasAccounts = (bool) $pdo->query(
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'accounts'"
)->fetchColumn();

$initialized = $hasAccounts && (bool) $pdo->query('SELECT EXISTS(SELECT 1 FROM accounts)')->fetchColumn();

echo $initialized ? 'initialized' : 'fresh';
