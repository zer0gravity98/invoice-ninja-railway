# Phase 0: Research findings and proposed architecture

Status: **awaiting approval before build** (per spec §12).
Researched 2026-09-27. Every claim cites the source it was checked against; items marked **UNVERIFIED** still need a live test on Railway.

Sources used:

- `invoiceninja/dockerfiles`, branch `debian` (default), commit `5bfcf75` (2026-09-17): `debian/Dockerfile`, `debian/scripts/init.sh`, `debian/supervisor/*.conf`, `debian/.env`, `debian/nginx/*.conf`, `charts/invoiceninja/values.yaml`
- `invoiceninja/invoiceninja`, branch `v5-stable`, commit `f1ffa5f` (2026-09-18): `config/ninja.php`, `config/filesystems.php`, `routes/api.php`, `app/Http/Middleware/TrustProxies.php`, `app/Console/Commands/CreateAccount.php`
- Invoice Ninja docs source (`invoiceninja/invoiceninja.github.io`): `docs/self-host/env-variables.md`
- Docker Hub API: `invoiceninja/invoiceninja-debian` tags
- Railway docs: `templates/create`, `databases/mysql`, `deployments/healthchecks`, `volumes/reference`, `storage-buckets`, `cron-jobs`, `networking/outbound-networking`
- Railway marketplace (via the Railway template API): `invoiceninja`, `invoice-ninja`, `invoice-ninja-5`, `invoice-ninja-billing`, `invoice-ninja-or-just-updated-freshbooks`

---

## 1. Image, processes and ports

| Item | Finding | Source |
|---|---|---|
| Image | `invoiceninja/invoiceninja-debian` (the Alpine `invoiceninja/invoiceninja` image is no longer the maintained one; `debian` is the repo's default branch) | dockerfiles README, branch list |
| Tag to pin | **`5.13.43`** (latest numbered tag, pushed 2026-09-18; `latest`, `5`, `5.13` point at the same digest). App reports `app_version` 5.13.43. | Docker Hub tags API; `config/ninja.php:23` |
| Base | `php:8.5-fpm` (Debian) | `debian/Dockerfile:1-3` |
| Processes | `supervisord` (PID 1 via `init.sh`) runs `php-fpm -F`, **2 × `queue:work`** (`--sleep=3 --tries=3 --max-time=3600`), and `schedule:work` | `debian/supervisor/programs.conf` |
| Ports | **php-fpm on 9000 only.** No HTTP server in the image. | `debian/Dockerfile` (HEALTHCHECK uses `cgi-fcgi` to 127.0.0.1:9000) |
| Web server | Upstream expects a **separate `nginx:alpine` container** that shares the `public` and `storage` volumes | `debian/docker-compose.yml` |
| PDF | `google-chrome-stable` (amd64) / `chromium` (arm64) plus Noto CJK and WQY fonts are baked in. `init.sh` exports `SNAPPDF_CHROMIUM_PATH` by architecture. | `debian/Dockerfile:30-50`, `debian/scripts/init.sh:3-8` |
| PHP limits | `memory_limit=512M`, `upload_max_filesize=10M`, `pm.max_children=10` | `debian/php/php.ini`, `php-fpm.conf` |

**Decision: bundle nginx in a thin custom Dockerfile** (`FROM invoiceninja/invoiceninja-debian:5.13.43`, `apt-get install nginx`, add an nginx supervisor program that listens on `$PORT`). Railway volumes can't be shared between services (`volumes/reference` → Caveats), so a separate nginx service couldn't see `public/storage` or uploaded files. All three serious competitors reached the same conclusion.

## 2. What upstream `init.sh` does, and the gaps for Railway

`init.sh` runs on every start when `APP_ENV=production`: it creates `storage/` subdirectories, refreshes `public/` from `/tmp/public`, recursively `chown`/`chmod`s `public` and `storage`, then runs `migrate --force`, `cache:clear`, `ninja:design-update` and `optimize`. On the first run (the `accounts` table exists but is empty) it runs `db:seed` and `ninja:create-account --email $IN_USER_EMAIL --password $IN_PASSWORD`.

Gaps we must close in our own entrypoint wrapper (which then `exec`s upstream `init.sh`):

1. **No wait for the database.** `migrate` fails immediately if MySQL isn't up yet. Because the script runs under `sh -e`, the container exits and Railway restarts it, which looks like a crash loop on first deploy. → Add a `mysqladmin ping` retry loop with a timeout.
2. **Hard fail when the admin creds are blank.** If either `IN_USER_EMAIL` or `IN_PASSWORD` is empty on first boot, it prints "Initialization failed" and `exit 1`. → The template always supplies `IN_PASSWORD` via `${{secret()}}`, and our wrapper fails early with a clear message if the email is missing.
3. **No HTTP server** (see §1).
4. **Upstream `/health` is useless as a DB check.** `routes/api.php:560` returns a static `{"status":"ok"}`, is throttled to 20 req/min, and never touches the DB. → Serve our own `/railway_health` (a tiny PHP file behind nginx) that runs `SELECT 1` via PDO and returns 503 on failure.
5. The recursive `chown`/`chmod` over `storage/` runs on every boot and will get slower as uploads grow. It's acceptable for now; revisit if boot time becomes a problem.

## 3. Environment variables

| Var | Value in template | Format / notes | Source |
|---|---|---|---|
| `APP_KEY` | `base64:${{secret(43, "A–Za–z0–9+/")}}=` | Laravel AES-256-CBC key: `base64:` + base64 of 32 bytes (44 chars incl. one `=`). Railway runs template functions **once at deploy** and stores the result as a normal variable, so it persists across restarts. | env-variables.md; Railway `templates/create` (this exact `openssl rand -base64 32` recipe is given there) |
| `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Also used for the `/storage` URL of uploads | `config/filesystems.php:72` |
| `APP_ENV` | `production` | Required for `init.sh` to migrate and seed at all | `init.sh` |
| `APP_DEBUG` | `false` | Upstream `.env` example has `true`, which is wrong for production (leaks stack traces) | `debian/.env` |
| `REQUIRE_HTTPS` | `true` | App default is `true`; upstream `.env` sets `false` for localhost | `config/ninja.php:20` |
| `TRUSTED_PROXIES` | `*` | Railway's edge IPs aren't fixed; `*` is what the docs recommend behind a proxy | env-variables.md; `TrustProxies.php:52` |
| `IS_DOCKER` | `true` | Enables Docker-specific tweaks (and disables the self-updater) | env-variables.md |
| `PDF_GENERATOR` | `snappdf` | "recommended way to generate PDFs" | env-variables.md |
| `PHANTOMJS_PDF_GENERATION` | `false` | | `debian/.env` |
| `SNAPPDF_CHROMIUM_PATH` | *(unset)* | Set by `init.sh` per arch | `init.sh` |
| `FILESYSTEM_DISK` | `debian_docker` | Local disk rooted at `storage/app/public`, URL `APP_URL/storage` | `config/filesystems.php:69` |
| `QUEUE_CONNECTION` | `database` | App default is `sync` (slow; blocks requests while PDFs/emails run) | env-variables.md |
| `CACHE_DRIVER` / `SESSION_DRIVER` | `file` / `file` | On the volume, so they survive restarts | — |
| `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | `mysql`, `${{MySQL.MYSQLHOST}}`, `${{MySQL.MYSQLPORT}}`, `${{MySQL.MYSQLDATABASE}}`, `${{MySQL.MYSQLUSER}}`, `${{MySQL.MYSQLPASSWORD}}` | Variable names confirmed in Railway MySQL docs. Note: Railway's MySQL template connects as `root`. | Railway `databases/mysql` |
| `IN_USER_EMAIL` | **required user input** | Read on first boot only | `init.sh`, dockerfiles README |
| `IN_PASSWORD` | `${{secret(20)}}` (user may override) | Read on first boot only; visible afterwards in the service's Variables tab | `init.sh` |
| `MAIL_MAILER` | `log` unless the user supplies SMTP | See §7 conflict | `debian/.env` |
| `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_ENCRYPTION`, `MAIL_FROM_ADDRESS`, `MAIL_FROM_NAME` | optional inputs | | env-variables.md |
| `PORT` | `8080` | nginx listens here; Railway also uses it for the healthcheck | Railway `deployments/healthchecks` |

## 4. What must persist

- **`/var/www/html/storage`** is the only volume. It holds uploads (logos, documents; `debian_docker` disk → `storage/app/public`), generated PDFs, file sessions and cache, and `storage/logs`.
- **`/var/www/html/public` does not need persisting.** Upstream only volumes it so the separate nginx can read it. `init.sh` rebuilds it from `/tmp/public` on every boot, and `public/storage` is a symlink into `storage/app/public` (created at build by `artisan storage:link`). With nginx in the same container, no second volume or extra symlink is needed.
- Logs: we'll send Laravel logs to stderr (`LOG_CHANNEL=stderr`) so they show in Railway's log view and don't grow forever on the volume.

## 5. Existing templates on the Railway marketplace

| Template | Deploys | What it ships | Weaknesses |
|---|---|---|---|
| **"Invoice Ninja [Updated Sep '26]"** (`invoiceninja`, shinyduo) | 22 | Custom repo image, MySQL 9.4, volume at `/var/www/app/storage` | **Hardcoded `APP_KEY` shared by every deployment** (a security hole). `QUEUE_CONNECTION=sync`, no admin seeding (setup wizard is open to whoever visits first), no backups, no PDF engine configured, README is SEO filler with no troubleshooting. |
| **"Invoice Ninja \| Open Source FreshBooks Alternative"** (`invoice-ninja`, Heimdall) | 9 | Debian image `:5` + bundled nginx, MySQL, **Redis**, volume at `/var/www/html/storage` | `APP_KEY` default is the literal placeholder `base64:CHANGE_ME_…` (invalid, so the app breaks unless the user replaces it). The README wrongly claims `${{secret()}}` re-evaluates on every read. Two required inputs (email and password). Unpinned `:5` tag. No backups. |
| **"Invoice Ninja 5 \| Invoicing with PDFs, Queue and Nightly Backups"** (`invoice-ninja-5`, nomideusz) | 0 | Debian `5.13.43` + nginx, MariaDB 11.8, bucket backups, one required input, generated `APP_KEY`/`IN_PASSWORD`, measured memory figures, SMTP-on-Pro caveat | The strongest one technically, and new. Backups run *inside* the app container (weekday rotation, so only 7 days). No separate cron service. |
| `invoice-ninja-billing` (A3A), `invoice-ninja-or-just-updated-freshbooks` (SuperSlowSloth) | 0 each | — | Not inspected in depth; zero deploys. |

**How we beat them:** pinned tag plus a generated, valid `APP_KEY` (vs #1/#2); a DB-aware health check (none have one); a DB wait loop; 14-day backups from a separate cron service that sleeps between runs, with a tested restore; SMTP/API email guidance; top-5 troubleshooting; and a maintenance note. `invoice-ninja-5` is close to this plan already, so we have to win on reliability proof (test report) and documentation, not on features.

## 6. Proposed architecture

```
                      Railway edge (TLS)
                            │  https://<app>.up.railway.app
                            ▼
┌──────────────────────── Invoice Ninja (A) ────────────────────────┐
│  FROM invoiceninja/invoiceninja-debian:5.13.43                    │
│  supervisord: nginx(:$PORT) · php-fpm(:9000) · queue ×2 · schedule│
│  entrypoint: wait-for-db → upstream init.sh (migrate, seed admin) │
│  healthcheck: /railway_health  (PDO SELECT 1 → 200/503)           │
│  volume: /var/www/html/storage                                    │
└───────────────┬───────────────────────────────────────────────────┘
                │ private network (${{MySQL.*}} refs)
                ▼
      ┌──── MySQL (B) ────┐          ┌──── Backup (D) ────────────────┐
      │ Railway MySQL     │◀─────────│ alpine + mysql-client + aws-cli │
      │ volume /var/lib/… │ mysqldump│ cron "15 3 * * *" (UTC), exits  │
      └───────────────────┘          │ gzip → bucket, keep newest 14   │
                                     └──────────────┬──────────────────┘
                                                    ▼
                                         Railway Bucket "Backups"
```

- **Redis (C): not included.** The database queue driver is persistent and needs no extra service, and Invoice Ninja's volume on a single node doesn't benefit from Redis' speed. Fewer services means fewer first-deploy failures and a lower bill. It can be documented as an optional upgrade.
- **Backup (D)** uses `${{Backups.ENDPOINT|BUCKET|ACCESS_KEY_ID|SECRET_ACCESS_KEY|REGION}}` references. Buckets don't support lifecycle rules (`storage-buckets` → "Not yet supported"), so the script prunes to 14 itself by listing and deleting the oldest objects. Users can override the `S3_*` vars to point at their own S3.

## 7. Conflicts with the spec, and things I couldn't verify

1. **SMTP is blocked on Railway Free, Trial and Hobby plans.** Railway docs: "SMTP is only available on the Pro plan and above… These services are required for Free, Trial, and Hobby plans since outbound SMTP is disabled." Spec §7 assumes SMTP inputs are enough. → Keep the optional `MAIL_*` inputs, but have the README lead with HTTP-API providers (Invoice Ninja supports Postmark/Mailgun/Brevo/SES per company under Settings → Email Settings) and label SMTP as Pro-only.
2. **The Railway healthcheck only runs at deploy time.** "The healthcheck endpoint is currently not used for continuous monitoring" (`deployments/healthchecks`). Checklist item "Healthcheck fails correctly if the database is down" can be proven (a deploy with the DB stopped is marked failed), but a live app won't be flagged if MySQL dies later. The README will say so and point to Uptime Kuma.
3. **The backup service can't see uploaded files.** A separate cron service has no access to the app's volume (volumes are one-service-only), so a DB dump alone misses logos and documents. Proposal: the cron service backs up the DB as specified, and the app container also pushes a nightly `storage/app` tarball to the same bucket. Otherwise we'd have to document that files aren't backed up. **Needs your call.**
4. **`APP_KEY` in backups.** A restore into a fresh deploy needs the old key, or encrypted gateway and mail credentials become unreadable. The README will tell users to copy it from the Variables tab. Should we also store it in the bucket, as `invoice-ninja-5` does? It's convenient but puts a secret in the bucket. My default is no: documented only.
5. **Memory at Railway default limits: UNVERIFIED.** Chrome is the main cost. A competitor reports ~0.7 GB after a burst of PDFs; the Free plan's 0.5 GB is reportedly not enough. This has to be measured on a test deploy.
6. **Marketplace title and description character limits: UNVERIFIED.** Not stated in the docs I found. I'll check in the template editor when we publish.
7. **The live checklist (§10) needs Railway access.** The Railway connector is available in this session, so I can create a test project to deploy and verify, with your go-ahead. Screenshots (§9) come from that test deploy.
8. **Repo visibility.** The repo is private. A marketplace template needs source anyone can deploy, so it has to be public before publishing (spec §11 also says "public GitHub repo").
