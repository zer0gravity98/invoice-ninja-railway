<?php

// Minimal S3 client for the backup scripts, using the AWS SDK that already
// ships with Invoice Ninja (vendor/aws/aws-sdk-php).
//
//   php s3.php put <local-file> <key>
//   php s3.php get <key> <local-file>
//   php s3.php latest <prefix>            prints the newest key under prefix
//   php s3.php list <prefix>              prints keys, oldest first
//   php s3.php prune <prefix> <keep>      deletes all but the newest <keep>
//
// Reads S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY,
// S3_REGION (default "auto") and S3_FORCE_PATH_STYLE (default false).
// Backup names embed a UTC timestamp, so key order is age order.

require '/var/www/html/vendor/autoload.php';

use Aws\S3\S3Client;

function fail(string $message): never
{
    fwrite(STDERR, "[s3] {$message}\n");
    exit(1);
}

foreach (['S3_ENDPOINT', 'S3_BUCKET', 'S3_ACCESS_KEY_ID', 'S3_SECRET_ACCESS_KEY'] as $var) {
    if (! getenv($var)) {
        fail("{$var} is not set");
    }
}

$bucket = getenv('S3_BUCKET');
$s3 = new S3Client([
    'version' => 'latest',
    'region' => getenv('S3_REGION') ?: 'auto',
    'endpoint' => getenv('S3_ENDPOINT'),
    'use_path_style_endpoint' => getenv('S3_FORCE_PATH_STYLE') === 'true',
    'credentials' => [
        'key' => getenv('S3_ACCESS_KEY_ID'),
        'secret' => getenv('S3_SECRET_ACCESS_KEY'),
    ],
]);

function keys(S3Client $s3, string $bucket, string $prefix): array
{
    $keys = [];
    foreach ($s3->getPaginator('ListObjectsV2', ['Bucket' => $bucket, 'Prefix' => $prefix]) as $page) {
        foreach ($page['Contents'] ?? [] as $object) {
            $keys[] = $object['Key'];
        }
    }
    sort($keys);

    return $keys;
}

[$command, $a, $b] = array_pad(array_slice($argv, 1), 3, null);

try {
    switch ($command) {
        case 'put':
            $s3->putObject(['Bucket' => $bucket, 'Key' => $b, 'SourceFile' => $a]);
            break;
        case 'get':
            $s3->getObject(['Bucket' => $bucket, 'Key' => $a, 'SaveAs' => $b]);
            break;
        case 'latest':
            $all = keys($s3, $bucket, (string) $a);
            $all ?: fail("no backups under {$a}");
            echo end($all), "\n";
            break;
        case 'list':
            foreach (keys($s3, $bucket, (string) $a) as $key) {
                echo $key, "\n";
            }
            break;
        case 'prune':
            $keep = max(1, (int) $b);
            foreach (array_slice(keys($s3, $bucket, (string) $a), 0, -$keep) as $key) {
                $s3->deleteObject(['Bucket' => $bucket, 'Key' => $key]);
                echo "deleted {$key}\n";
            }
            break;
        default:
            fail('usage: s3.php put|get|latest|list|prune ...');
    }
} catch (Aws\Exception\AwsException $e) {
    fail($e->getAwsErrorCode() ?: $e->getMessage());
}
