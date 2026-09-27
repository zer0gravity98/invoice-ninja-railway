# Test report

Template version 1.0.0 (Invoice Ninja 5.13.43), tested 2026-09-27.

Two environments:

- **Local:** the image built from this repo, run with Docker against `mysql:9.4` (Railway's MySQL image, same start flags).
- **Railway:** test project `invoice-ninja-template-test`, set up exactly as [template-config.md](template-config.md) describes (Railway MySQL template, `Backups` bucket, Invoice Ninja and Backup services built from this repo). Checks ran from a throwaway Railway Function in the same project calling the public HTTPS URL, because the sandbox the build ran in can't reach `*.up.railway.app`.

## Acceptance checklist

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Fresh deploy with only an email reaches a working login page, no manual commands | **Pass** | Railway: deploy went *Active* through the `/railway_health` check. Container start to healthy took ~33 s (`MySQL is reachable (install state: fresh)` at 21:16:04 → `supervisord started` at 21:16:36). |
| 2 | Admin can log in with the documented credentials | **Pass** | `[test] login 200` using `IN_USER_EMAIL` and `IN_PASSWORD` from the service variables. |
| 3 | Create client and invoice, download PDF; PDF renders with logo and fonts | **Pass** | `[test] client 200`, `[test] invoice 0012 300`, `[test] pdf (no logo) {"bytes":78866,"isPdf":true,…,"fonts":["Roboto-Regular","WenQuanYiZenHei"]} 1203ms`. After uploading a 544 px logo: `pdf (with logo) {"bytes":101960,"images":["544","544",…]}`, so Chrome fetched the logo over `https://APP_URL/storage/…` and embedded it. Local render checked visually: Latin, accented and CJK text all render (`Ünïcödé 日本語`). |
| 4 | Upload a logo, redeploy/restart: logo and data still there | **Pass** | Logo stored on the volume (`storage/app/public/…png`) and served: `[test] logo fetch 200 image/png`. After 3 restarts: `[test] company_logo https://…/storage/…png`, `logo still served 200`, `invoices in db 13`. |
| 5 | Restart the app 3 times: `APP_KEY` unchanged, existing data readable | **Pass** | 3 × Railway restart (21:21:15, 21:21:44, 21:22:10), each `install state: initialized` with no key error. A Stripe gateway created before the restarts (config encrypted with `APP_KEY`) still decrypts: `[test] gateway config decrypts true`. Local: the same key fingerprint (`f8f75367…`) on 3 restarts. |
| 5b | Changed `APP_KEY` is caught | **Pass** (local) | New random key on an existing install: `[railway] ERROR: APP_KEY differs from the key this install was created with…` and the container exits. A malformed key: `APP_KEY must be 32 bytes …, got 6.` |
| 6 | Queue works (email with log mailer); scheduler runs | **Pass** | `App\Services\Email\Email 95 database default … DONE`, followed by the logged mail `To: Ann <ann@example.com>` / `Subject: Template test invoice`. `Running scheduled tasks` appears in the logs from `schedule:work`. |
| 7 | Backup cron runs, uploads a compressed dump, prunes beyond 14; restore into a fresh MySQL | **Pass** | Railway, cron temporarily every 5 min: `[backup-db] uploaded invoiceninja/db/invoiceninja-db-20260927T212515Z.sql.gz (83733 bytes)`. Pruning with `BACKUP_KEEP=2`: the third run logged `deleted invoiceninja/db/invoiceninja-db-20260927T212515Z.sql.gz`, and the fourth deleted the next oldest. Restore: `restore-db latest --yes` into a new, empty database on the same MySQL server downloaded the newest dump, restored it and ran migrations (`Nothing to migrate`). Row counts matched the live database (invoices 13/13, clients 12/12, gateways 1/1, migrations 319/319). Local: a dump restored into a separate, fresh `mysql:9.4` container with matching row counts. |
| 8 | Healthcheck fails if the database is down | **Pass** | Railway: `DB_HOST` pointed at a name that doesn't resolve. The new deploy logged `waiting for MySQL at db-down-test.railway.internal:3306 …` for 30 s, then `ERROR: Could not reach MySQL`, and restarted without ever passing `/railway_health`. Local, MySQL stopped while running: `/railway_health` → `503 {"status":"error","error":"Illuminate\\Database\\QueryException"}`. **Note:** because the service has a volume, Railway stops the old deployment before starting the new one, so the site returned `502 Application failed to respond` during the failed deploy. The README says so and explains how to redeploy the last working version. |
| 9 | No secrets in logs or README; HTTPS links, no mixed content | **Pass** | Entrypoint logs name variables, never values. `health.php` returns only the exception class. The README has no credentials. Email and asset links in the logs all use `https://invoice-ninja-production-19bf.up.railway.app/…`. |
| 10 | A second independent copy works | *Pending* | Runs once the template exists in Railway, by deploying it into a new project. |

## Memory

Measured locally (`docker stats`): Invoice Ninja **~560 MB** idle, **1.33 GB** peak while rendering 5 PDFs at once, back to ~575 MB afterwards. MySQL ~270 MB.

## Issues found and fixed during testing

- nginx failed to start on hosts without IPv6 (`socket() [::]:8080 failed (97)`). The IPv6 listener is now added only when the container has IPv6.
- Railway rejects `/railway-health` as a healthcheck path (hyphens aren't allowed), so the path is `/railway_health`.
