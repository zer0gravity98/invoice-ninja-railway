# Railway template configuration

Everything to enter in the Railway template composer (Workspace → Templates → New, or **Generate Template from Project** on a working test project). Railway's `railway.json` config-as-code is deprecated and stops being read on 2026-12-01, so these settings live in the template itself.

Template variable functions: `${{secret(n, alphabet)}}` is evaluated **once, when a user deploys** the template, and stored as an ordinary variable ([docs](https://docs.railway.com/templates/create#template-variable-functions)). That's what keeps `APP_KEY` stable across restarts.

## Services

### Invoice Ninja

| Setting | Value |
|---|---|
| Source | GitHub `zer0gravity98/invoice-ninja-railway`, branch `main` (repo must be public) |
| Builder | Dockerfile (auto-detected at repo root) |
| Volume | mount path `/var/www/html/storage` |
| Public networking | HTTP, generated domain, target port `8080` |
| Healthcheck path | `/railway_health` (Railway allows only letters, digits, `/` and `_`) |
| Healthcheck timeout | `600` seconds |
| Restart policy | On failure, max 10 retries |

| Variable | Value | Shown to user? |
|---|---|---|
| `IN_USER_EMAIL` | *(empty, required)*. Description: "Your email address: the login for the admin account created on first boot." | **Yes, required** |
| `IN_PASSWORD` | `${{secret(20, "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")}}` | Optional, pre-filled |
| `APP_KEY` | `base64:${{secret(43, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/")}}=` | Hidden |
| `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Hidden |
| `PORT` | `8080` | Hidden |
| `DB_HOST` | `${{MySQL.MYSQLHOST}}` | Hidden |
| `DB_PORT` | `${{MySQL.MYSQLPORT}}` | Hidden |
| `DB_DATABASE` | `${{MySQL.MYSQLDATABASE}}` | Hidden |
| `DB_USERNAME` | `${{MySQL.MYSQLUSER}}` | Hidden |
| `DB_PASSWORD` | `${{MySQL.MYSQLPASSWORD}}` | Hidden |
| `S3_ENDPOINT` | `${{Backups.ENDPOINT}}` | Hidden |
| `S3_BUCKET` | `${{Backups.BUCKET}}` | Hidden |
| `S3_REGION` | `${{Backups.REGION}}` | Hidden |
| `S3_ACCESS_KEY_ID` | `${{Backups.ACCESS_KEY_ID}}` | Hidden |
| `S3_SECRET_ACCESS_KEY` | `${{Backups.SECRET_ACCESS_KEY}}` | Hidden |
| `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_ENCRYPTION`, `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME` | *(empty)*. Description: "Optional SMTP (Railway Pro plan only). Leave blank to log emails; see README." | Optional |

`APP_KEY` format: Laravel wants `base64:` plus 32 random bytes in base64. Forty-three characters from the base64 alphabet plus one `=` is exactly that (it's Railway's documented recipe for `openssl rand -base64 32`). The entrypoint rejects any key that doesn't decode to 32 bytes.

Everything else (`APP_ENV`, `REQUIRE_HTTPS`, `TRUSTED_PROXIES`, `PDF_GENERATOR`, `QUEUE_CONNECTION`, …) has a default in the `Dockerfile`. See the variable table in [phase-0-findings.md](phase-0-findings.md).

### MySQL

Railway's MySQL database (`mysql:9.4`, volume at `/var/lib/mysql`). Keep the template's own variables (`MYSQL_ROOT_PASSWORD` = `${{secret(32, …)}}`, `MYSQL_DATABASE` = `railway`, and the `MYSQL*` connection variables). No public networking.

### Backup

| Setting | Value |
|---|---|
| Source | Same repo and branch as Invoice Ninja (same image, so dump and restore use the same tools) |
| Start command | `/usr/local/bin/backup-db` |
| Cron schedule | `15 3 * * *` (03:15 UTC) |
| Restart policy | Never |
| Volume, networking, healthcheck | None |

Variables: the same `DB_*` and `S3_*` references as the Invoice Ninja service, plus `BACKUP_KEEP` = `14`.

### Backups (bucket)

A Railway Bucket named `Backups`. The name matters, because the `S3_*` references use it.

## Listing

- **Name:** Invoice Ninja | One-Click Invoicing with Working PDFs, Queue & Daily Backups
- **Short description:** Free self-hosted FreshBooks/QuickBooks alternative that works on first deploy: PDFs, queue, and nightly backups.
- **Category:** Other (the same category most Invoice Ninja templates use; Automation is the other option)
- **README:** the repo's `README.md`
- **Screenshots:** dashboard, invoice editor, generated PDF (from the test deploy)
