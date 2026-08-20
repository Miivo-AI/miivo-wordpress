# pinned to the 7.0.x line: patch/security releases still flow on redeploy,
# but major/minor core bumps (and the "Database Update Required" screen they
# trigger) only happen when this tag is bumped deliberately. after bumping,
# visit /wp-admin/upgrade.php once to run the one-click db migration.
FROM wordpress:7.0-php8.2-apache


RUN apt-get update && apt-get install -y magic-wormhole

# this host is a headless CMS backend for www.miivo.ai and must never be
# indexed by search engines (see noindex.conf). the render disk mounted at
# /var/www/html shadows files baked into the docroot, so robots.txt lives
# under /opt and is served via an apache alias.
COPY noindex.conf /etc/apache2/conf-available/noindex.conf
COPY robots-staging.txt /opt/staging/robots.txt
RUN a2enmod headers && a2enconf noindex

# apache worker cap + timeouts sized for the render instance (perf.conf),
# static /healthz target for the render health check (healthz.conf), and a
# php execution ceiling. all outside /var/www/html because the disk shadows
# the docroot. conf-enabled loads after mods-enabled, so perf.conf wins over
# the stock mpm_prefork values.
COPY perf.conf /etc/apache2/conf-available/perf.conf
COPY healthz.conf /etc/apache2/conf-available/healthz.conf
COPY healthz.txt /opt/healthz/healthz
COPY php-perf.ini /usr/local/etc/php/conf.d/miivo-perf.ini
RUN a2enconf perf healthz

RUN usermod -s /bin/bash www-data
RUN chown -R www-data:www-data /var/www

# run as root (the official image's default): the entrypoint must be able to
# chown/chmod the render disk mounted at /var/www/html on first boot — as
# www-data the wordpress copy fails ("tar: .: Cannot change mode to rwxrwxr-x:
# Operation not permitted") and the deploy exits with status 2. apache worker
# processes still run as www-data; only pid 1 and the entrypoint are root.
