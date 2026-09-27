<?php

// Railway deploy healthcheck, served at /railway_health.
//
// Upstream's /health route returns a static "ok" without touching the
// database, so a deploy with a broken DB connection would still go live.
// This boots Laravel with the app's real (cached) config and returns 200
// only when MySQL answers and first-boot setup has created the admin
// account; anything else is a 503 and Railway marks the deploy failed.

header('Content-Type: application/json');
header('Cache-Control: no-store');

try {
    require '/var/www/html/vendor/autoload.php';
    $app = require '/var/www/html/bootstrap/app.php';
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

    Illuminate\Support\Facades\DB::select('SELECT 1');

    if (! App\Models\Account::query()->exists()) {
        http_response_code(503);
        echo json_encode(['status' => 'initializing']);

        return;
    }

    echo json_encode(['status' => 'ok']);
} catch (Throwable $e) {
    // Only the exception class: messages can contain hostnames or usernames.
    error_log('railway_health: '.get_class($e));
    http_response_code(503);
    echo json_encode(['status' => 'error', 'error' => get_class($e)]);
}
