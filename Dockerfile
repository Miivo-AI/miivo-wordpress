# pinned to the 7.1.x line. docker hub only rebuilds the newest wordpress
# minor line, so once 7.2 ships this tag stops getting php/apache security
# fixes and must be bumped (the 7.0 tag froze on php 8.2.33 and missed the
# php2shell fix in 8.2.35). a bump also updates wordpress core: on boot,
# miivo-entrypoint.sh copies the image's core over the render disk when it
# is newer and runs the db upgrade.
FROM wordpress:7.1-php8.2-apache

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

# hardening after the 2026-09-05 wp2shell compromise: no php from uploads,
# no xml-rpc (hardening.conf). wp-cli plus a read-only disk audit that runs
# at boot and prints to the render logs (miivo-audit.sh), because the render
# disk is only reachable from inside the container.
COPY hardening.conf /etc/apache2/conf-available/hardening.conf
RUN a2enconf hardening
RUN curl -fsSL -o /usr/local/bin/wp https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar \
	&& echo "be928f6b8ca1e8dfb9d2f4b75a13aa4aee0896f8a9a0a1c45cd5d2c98605e6172e6d014dda2e27f88c98befc16c040cbb2bd1bfa121510ea5cdf5f6a30fe8832  /usr/local/bin/wp" | sha512sum -c - \
	&& chmod +x /usr/local/bin/wp
COPY miivo-audit.sh miivo-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/miivo-audit.sh /usr/local/bin/miivo-entrypoint.sh
ENTRYPOINT ["miivo-entrypoint.sh"]
CMD ["apache2-foreground"]

RUN usermod -s /bin/bash www-data
RUN chown -R www-data:www-data /var/www

# run as root (the official image's default): the entrypoint must be able to
# chown/chmod the render disk mounted at /var/www/html on first boot — as
# www-data the wordpress copy fails ("tar: .: Cannot change mode to rwxrwxr-x:
# Operation not permitted") and the deploy exits with status 2. apache worker
# processes still run as www-data; only pid 1 and the entrypoint are root.
