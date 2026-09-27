# Invoice Ninja on Railway

One-click [Invoice Ninja](https://invoiceninja.com) v5: a free, self-hosted alternative to FreshBooks and QuickBooks for invoices, quotes, payments, expenses and time tracking. Enter your email, click Deploy, and log in about two minutes later. Working PDFs, a running queue and nightly backups are included.

**Pinned version:** Invoice Ninja **5.13.43** (`invoiceninja/invoiceninja-debian:5.13.43`). See [CHANGELOG.md](CHANGELOG.md).

## What's included

```
                 https://<your-app>.up.railway.app
                               │
┌──────────────────────── Invoice Ninja ─────────────────────────┐
│ nginx · php-fpm · 2 queue workers · scheduler · Chrome (PDFs)  │
│ volume: /var/www/html/storage (uploads, PDFs, sessions)        │
│ nightly: uploaded files ──────────────────────────┐            │
└──────────────┬─────────────────────────────────────┼────────────┘
               │ private network                     ▼
        ┌─── MySQL ───┐   mysqldump   ┌─ Backup (cron 03:15 UTC) ─┐   ┌─ Backups bucket ─┐
        │ mysql:9.4   │◀──────────────│ runs, uploads, exits      │──▶│ 14 DB dumps      │
        │ + volume    │               └───────────────────────────┘   │ 14 file archives │
        └─────────────┘                                               └──────────────────┘
```

| Service | What it does |
|---|---|
| **Invoice Ninja** | The official image plus nginx, so one service serves the app and runs the queue workers and scheduler. |
| **MySQL** | Railway's MySQL, reachable only over the private network. |
| **Backup** | Runs once a night, dumps the database to the bucket, keeps 14, and exits. |
| **Backups** (bucket) | Railway Bucket (S3-compatible) holding database dumps and uploaded-file archives. |

There's no Redis. The database queue survives restarts and is one less service to break or pay for.

## Quick start

1. Click **Deploy**, enter the email you want to log in with (`IN_USER_EMAIL`), and deploy.
2. Wait until the **Invoice Ninja** service shows *Active*. First boot creates the database tables and your account, which takes a minute or two.
3. Open the service's URL and log in with your email and the generated password (see below).

### Where to find the admin password

Open the **Invoice Ninja** service, go to **Variables**, and copy `IN_PASSWORD`. It's only used on first boot, so after logging in change your password under **Settings → User Details**. Changing the variable later does nothing.

Lost it? Use **Forgot password** on the login page. Until email is set up, the reset email is written to the service's **Deploy Logs**; search for `reset` and open the link.

## Email

Until you configure email, `MAIL_MAILER` is `log`: the app works, but emails (invoices, reminders, password resets) are written to the logs instead of being sent.

**Railway blocks outbound SMTP on the Free, Trial and Hobby plans** ([docs](https://docs.railway.com/networking/outbound-networking#email-delivery)). On those plans, send through a provider's HTTP API, which Invoice Ninja supports per company:

- **Settings → Email Settings → Email Provider**: choose Postmark, Mailgun, Brevo or Amazon SES and paste the API key. This covers invoices, quotes and reminders.

On the **Pro plan** you can use SMTP for all mail by setting these variables on the Invoice Ninja service (setting `MAIL_HOST` switches the mailer to SMTP automatically):

| Variable | Resend | Brevo |
|---|---|---|
| `MAIL_HOST` | `smtp.resend.com` | `smtp-relay.brevo.com` |
| `MAIL_PORT` | `587` | `587` |
| `MAIL_USERNAME` | `resend` | your Brevo SMTP login |
| `MAIL_PASSWORD` | your Resend API key | your Brevo SMTP key |
| `MAIL_ENCRYPTION` | `tls` | `tls` |
| `MAIL_FROM_ADDRESS` | an address on your verified domain | an address on your verified domain |
| `MAIL_FROM_NAME` | your company name | your company name |

## Custom domain

1. On the **Invoice Ninja** service, open **Settings → Networking → Custom Domain**, add your domain, and create the DNS record Railway shows.
2. Under **Variables**, change `APP_URL` to `https://your.domain` and redeploy.

`APP_URL` is used in emails, the client portal and links to uploaded files, so it must be the address people actually use.

## Backups and restore

Every night at **03:15 UTC** the Backup service dumps the database to the bucket, and at **03:30 UTC** the app uploads `storage/app` (logos, documents). The newest **14** of each are kept, under `invoiceninja/db/` and `invoiceninja/files/`. You can browse and download them from the bucket's **Files** tab.

To take a backup right now, before an upgrade for example, run `backup-db` and `backup-files` in a `railway ssh` session on the Invoice Ninja service. It has the same tools and credentials as the Backup service.

**Restore** (from a `railway ssh` session on the Invoice Ninja service):

```sh
restore-db                 # list database backups
restore-db latest --yes    # restore the newest (or pass a key from the list)
restore-files latest --yes # restore uploaded files
```

Then restart the Invoice Ninja service.

**Keep a copy of your `APP_KEY`** (Invoice Ninja service → Variables) somewhere safe, such as a password manager. Payment gateway, bank and email credentials are encrypted with it. Backups don't include it, so to restore into a *new* deployment, set that deployment's `APP_KEY` to the old value before restoring. The app refuses to start if `APP_KEY` changes on an existing install. Set `ALLOW_APP_KEY_CHANGE=true` only if you rotated it on purpose.

To restore into a fresh MySQL, point the Invoice Ninja service's `DB_*` variables at it and run `restore-db latest --yes`.

## Upgrading Invoice Ninja

1. Take a backup (see above).
2. In your fork of this repo, change the tag in the `FROM invoiceninja/invoiceninja-debian:…` line of the `Dockerfile` to the new version, and add a line to `CHANGELOG.md`.
3. Push. Railway rebuilds, and migrations run automatically on boot.

Because the service has a volume, Railway stops the running version before starting the new one, so there's a short outage on every deploy. If the new version fails its healthcheck, the site stays down until you fix it or redeploy the previous version from the service's **Deployments** tab. That's why step 1 matters.

Invoice Ninja's built-in updater is disabled in Docker installs, so this is the way to upgrade. [docs/maintenance.md](docs/maintenance.md) has the full checklist.

## Resources and cost

Measured with this image (Invoice Ninja 5.13.43):

| | Memory |
|---|---|
| Invoice Ninja, idle | ~560 MB |
| Invoice Ninja, 5 PDFs rendering at once | ~1.3 GB peak |
| MySQL | ~270 MB |
| Backup | runs for seconds a night |

Plan on **1 GB** of memory for light use and **2 GB** if you generate several PDFs at once. The Free plan's 0.5 GB per service isn't enough for Chrome. Railway bills for actual usage. A small business install idles at well under the Hobby plan's included usage, plus volume and bucket storage, which starts at a few hundred MB.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Deploy fails with *Healthcheck failed* and the site shows *Application failed to respond* | Open the Deploy Logs and find the `[railway] ERROR` line, which says what's wrong. Most often MySQL isn't up yet (the app waits 3 minutes; redeploy once MySQL is *Active*) or a `DB_*` variable was edited. To get back online quickly, redeploy the last working version from the **Deployments** tab. |
| `APP_KEY differs from the key this install was created with` | `APP_KEY` was changed. Put the original value back. Only set `ALLOW_APP_KEY_CHANGE=true` if you meant to rotate it; stored gateway and email passwords will then need re-entering. |
| PDFs are blank, fail, or the service restarts while generating them | Chrome ran out of memory. Give the service at least 1 GB (2 GB for bursts) under **Settings → Resources**. |
| Emails don't arrive | `MAIL_MAILER` is `log` (look for the mail in Deploy Logs), or you're using SMTP on a plan that blocks it. See [Email](#email). |
| Logos or links point to the wrong address, or the browser warns about mixed content | `APP_URL` doesn't match the address in your browser. Set it to your exact `https://` URL and redeploy. |

## How it works

- **`Dockerfile`**: the pinned official image, plus nginx copied from the official `nginx:1.29.8-trixie` image and a few scripts. Railway builds it straight from this repo.
- **`app/railway-entrypoint.sh`**: runs on every start. It checks `APP_KEY` and the `DB_*` variables, waits for MySQL, stops if `APP_KEY` changed, then hands over to the upstream `init.sh` (migrations, admin account, caches).
- **`/railway_health`**: the deploy healthcheck. It boots Laravel and queries MySQL, returning 503 until your account exists. Railway only checks it during a deploy; it doesn't monitor a running service.
- **`app/backup-db`, `app/backup-files`, `app/restore-*`**: the backup and restore commands. They use the MariaDB client and AWS SDK that ship in the image.

The template's services and variables are listed in [docs/template-config.md](docs/template-config.md).

## License

This template's files are MIT licensed. Invoice Ninja itself is licensed under the [Elastic License 2.0](https://github.com/invoiceninja/invoiceninja/blob/v5-stable/LICENSE).
