#!/bin/sh
# Railway wrapper around the upstream entrypoint (/usr/local/bin/init.sh).
#
# Adds what a one-click deploy needs before upstream migrates and seeds:
#   1. validate APP_KEY and the DB settings, with readable errors
#   2. render the nginx config for Railway's $PORT
#   3. wait for MySQL instead of crash-looping while it starts
#   4. refuse to boot if APP_KEY changed on an existing install
#   5. fail early (not mid-seed) if first boot has no admin credentials
# Every step is safe to repeat on each restart.
set -eu

log() { echo "[railway] $*"; }
die() { echo "[railway] ERROR: $*" >&2; exit 1; }

# Only wrap the default command; `railway ssh` one-offs etc. pass straight through.
if [ "$*" != 'supervisord -c /etc/supervisor/supervisord.conf' ]; then
    exec /usr/local/bin/init.sh "$@"
fi

STORAGE=/var/www/html/storage
PORT="${PORT:-8080}"

# 1. Configuration checks
[ -n "${APP_KEY:-}" ] || die "APP_KEY is empty. Set it on the Invoice Ninja service (the template generates one)."
case "$APP_KEY" in
    base64:*) key_bytes=$(printf '%s' "${APP_KEY#base64:}" | base64 -d 2>/dev/null | wc -c) ;;
    *) key_bytes=$(printf '%s' "$APP_KEY" | wc -c) ;;
esac
[ "$key_bytes" -eq 32 ] || die "APP_KEY must be 32 bytes (base64: followed by 32 base64-encoded bytes), got $key_bytes."

for var in DB_HOST DB_DATABASE DB_USERNAME DB_PASSWORD; do
    eval "val=\${$var:-}"
    [ -n "$val" ] || die "$var is empty. It should reference the MySQL service, e.g. \${{MySQL.MYSQLHOST}}."
done

# Email: SMTP when a host is given, otherwise write mail to the logs so the
# app still boots and queued emails don't fail.
if [ -z "${MAIL_MAILER:-}" ]; then
    if [ -n "${MAIL_HOST:-}" ]; then MAIL_MAILER=smtp; else MAIL_MAILER=log; fi
    export MAIL_MAILER
fi
[ "$MAIL_MAILER" = log ] && log "MAIL_MAILER=log: emails are written to the logs, not sent. See README > Email."

case "${APP_URL:-}" in
    https://?*) ;;
    *) log "WARNING: APP_URL is '${APP_URL:-}'. Links, PDFs and assets need the public https:// URL." ;;
esac

# 2. nginx listens on Railway's $PORT
# (IPv6 too when the container has it: Railway's private network is IPv6.)
listen_v6=""
[ -f /proc/net/if_inet6 ] && listen_v6="listen [::]:$PORT default_server;"
sed -e "s/__PORT__/$PORT/g" -e "s/__LISTEN_V6__/$listen_v6/" \
    /opt/railway/nginx.conf.template > /etc/nginx/conf.d/invoiceninja.conf
nginx -t -q

# 3. Wait for MySQL
state=$(php /opt/railway/wait-for-db.php) || die "Could not reach MySQL. Check that the MySQL service is running."
log "MySQL is reachable (install state: $state)"

# 4. APP_KEY guard. Changing the key makes stored gateway, bank and mail
# credentials unreadable, so an unexpected change stops the boot instead.
mkdir -p "$STORAGE"
fingerprint_file="$STORAGE/.railway-app-key-sha256"
fingerprint=$(printf '%s' "$APP_KEY" | sha256sum | cut -c1-16)
if [ "$state" = initialized ] && [ -f "$fingerprint_file" ] \
    && [ "$(cat "$fingerprint_file")" != "$fingerprint" ] \
    && [ "${ALLOW_APP_KEY_CHANGE:-false}" != true ]; then
    die "APP_KEY differs from the key this install was created with. Restore the original APP_KEY, or set ALLOW_APP_KEY_CHANGE=true if you changed it on purpose."
fi
printf '%s' "$fingerprint" > "$fingerprint_file"

# 5. First boot needs the admin credentials
if [ "$state" = fresh ]; then
    [ -n "${IN_USER_EMAIL:-}" ] || die "IN_USER_EMAIL is empty. Set it to the email you want to log in with."
    [ -n "${IN_PASSWORD:-}" ] || die "IN_PASSWORD is empty. Set a password (the template generates one) and redeploy."
    log "First boot: creating the admin account for $IN_USER_EMAIL"
fi
export IN_USER_EMAIL="${IN_USER_EMAIL:-}" IN_PASSWORD="${IN_PASSWORD:-}"

# Upstream only creates some storage dirs; a fresh Railway volume is empty.
mkdir -p "$STORAGE/logs" "$STORAGE/app/public"

exec /usr/local/bin/init.sh "$@"
