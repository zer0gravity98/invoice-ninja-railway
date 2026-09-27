# Maintenance: keeping the template current

Stale templates lose deploys. Check for a new Invoice Ninja release roughly monthly, and within a few days of a security release.

## Bump the pinned version

1. Find the new tag: https://hub.docker.com/r/invoiceninja/invoiceninja-debian/tags. Use a full version such as `5.13.50`, never `latest` or `5`.
2. Read the release notes (https://github.com/invoiceninja/invoiceninja/releases) and the `debian` branch of https://github.com/invoiceninja/dockerfiles for changes to:
   - `debian/scripts/init.sh`: our entrypoint hands over to it, and relies on the `supervisord -c /etc/supervisor/supervisord.conf` command check and the `IN_USER_EMAIL`/`IN_PASSWORD` first-boot logic.
   - `debian/supervisor/*.conf`: we add `nginx` and `files-backup` programs next to upstream's.
   - `debian/Dockerfile`: a Debian major-version change means bumping the `nginx:…-trixie` stage to the matching suffix too, because the nginx binary is copied across.
3. On a branch, change `FROM invoiceninja/invoiceninja-debian:<tag>` in `Dockerfile` and add a `CHANGELOG.md` entry.

## Test

Deploy the branch to a throwaway Railway project, either by deploying the template and pointing both repo services at the branch, or by creating a test project the same way as [template-config.md](template-config.md). Then check:

- [ ] Fresh deploy with only an email reaches the login page; the admin can log in.
- [ ] Create a client and an invoice, and download the PDF: it renders with the logo and fonts.
- [ ] Upgrade path: deploy the **old** tag, create data, switch to the new tag, and redeploy. Migrations run, data is intact, and the log shows no `APP_KEY` error.
- [ ] Restart the app: `APP_KEY` guard passes and data is readable.
- [ ] Run the Backup service once; a new `invoiceninja/db/…sql.gz` appears in the bucket.
- [ ] `railway ssh` → `restore-db latest --yes` succeeds.

Record the results in `docs/test-report.md`.

## Release

1. Merge to `main`. Deployed copies that follow this repo rebuild on their next deploy, while the template itself always deploys `main`.
2. Update the pinned version in the template listing's README if it's mentioned there.
3. Delete the throwaway test project.

## Other things that go stale

- **Railway MySQL image** (`mysql:9.4` in Railway's MySQL template): the backup client is MariaDB's `mariadb-dump` from the app image. After Railway moves to a new MySQL major, run a backup and restore once to confirm compatibility.
- **Railway platform changes**: healthcheck path rules, template variable functions and cron behaviour are documented in `docs/template-config.md`, with sources. Re-check them when something fails in a way the logs don't explain.
