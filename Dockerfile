# Invoice Ninja for Railway.
#
# The official image runs php-fpm, two queue workers and the scheduler under
# supervisord, but no web server: upstream pairs it with a separate nginx
# container that shares the public/ and storage/ volumes. Railway volumes
# attach to exactly one service, so nginx runs in this container instead.
#
# To upgrade Invoice Ninja, change this tag (see docs/maintenance.md).
FROM nginx:1.29.8-trixie AS nginx

FROM invoiceninja/invoiceninja-debian:5.13.43

# nginx is copied from the official image rather than apt-installed: both are
# Debian 13 (trixie), and every shared library it links is already in the base
# image, so the build needs no package mirror and is fully pinned.
COPY --from=nginx /usr/sbin/nginx /usr/sbin/nginx
COPY --from=nginx /etc/nginx/mime.types /etc/nginx/fastcgi_params /etc/nginx/
COPY app/nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /etc/nginx/conf.d /var/cache/nginx /var/log/nginx \
    && nginx -V

# Sane production defaults. Everything here can be overridden with a Railway
# variable; the template sets the per-deploy values (APP_KEY, APP_URL, DB_*).
ENV APP_ENV=production \
    APP_DEBUG=false \
    IS_DOCKER=true \
    REQUIRE_HTTPS=true \
    TRUSTED_PROXIES=* \
    PDF_GENERATOR=snappdf \
    PHANTOMJS_PDF_GENERATION=false \
    FILESYSTEM_DISK=debian_docker \
    QUEUE_CONNECTION=database \
    CACHE_DRIVER=file \
    SESSION_DRIVER=file \
    LOG_CHANNEL=stderr \
    MAIL_MAILER=log \
    DB_CONNECTION=mysql \
    DB_PORT=3306 \
    PORT=8080

COPY app/nginx.conf.template /opt/railway/nginx.conf.template
COPY app/php-fpm-railway.conf /usr/local/etc/php-fpm.d/zzz-railway.conf
COPY app/supervisor-railway.conf /etc/supervisor/conf.d/railway.conf
COPY --chmod=0644 app/health.php app/wait-for-db.php app/s3.php /opt/railway/
COPY --chmod=0755 app/railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY --chmod=0755 app/backup-db app/backup-files app/backup-files-loop app/restore-db app/restore-files /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
# Must match the string upstream init.sh checks before it runs first-boot setup.
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
