# Changelog

All notable changes to this template. Invoice Ninja's own release notes are at
https://github.com/invoiceninja/invoiceninja/releases.

## 1.0.0 (unreleased)

- Invoice Ninja **5.13.43** (`invoiceninja/invoiceninja-debian:5.13.43`), PHP 8.5, Debian 13.
- nginx 1.29.8 bundled into the app container, so one Railway service serves the web UI and runs the queue workers and scheduler.
- First boot is fully automatic: waits for MySQL, migrates, and creates the admin account from `IN_USER_EMAIL` and a generated `IN_PASSWORD`.
- `APP_KEY` is generated once at deploy. The app refuses to start if it later changes on an existing install.
- `/railway-health` deploy healthcheck that fails when MySQL is unreachable.
- Database queue (no Redis) and file sessions/cache on the volume.
- Nightly database dumps (Backup cron service) and uploaded-file archives (app container) to a Railway Bucket, keeping 14 of each. `restore-db` and `restore-files` commands are included.
