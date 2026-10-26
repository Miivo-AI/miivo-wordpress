#!/bin/bash
# boot wrapper around the stock entrypoint, for the web server only (one-off
# jobs pass their own command and skip all of this).
#
# 1. keep wordpress core in step with the image. the render disk shadows the
#    docroot, so the stock entrypoint never replaces core once it exists, and
#    an image bump alone left the site on a vulnerable core (wp2shell,
#    2026-09-05). when the image ships a newer core than the disk, copy it over
#    (wp-content, wp-config.php and .htaccess are untouched) and run the db
#    upgrade.
# 2. give the docroot to www-data so wordpress can apply its own minor
#    security updates between image bumps.
# 3. start the read-only disk audit in the background.
set -u
DOCROOT=/var/www/html
SRC=/usr/src/wordpress

core_version() {
	php -r 'include $argv[1]; echo $wp_version;' "$1/wp-includes/version.php" 2>/dev/null
}

sync_core() {
	[ -f "$DOCROOT/wp-includes/version.php" ] || return 0
	local disk image
	disk=$(core_version "$DOCROOT")
	image=$(core_version "$SRC")
	if ! php -r 'exit(version_compare($argv[1], $argv[2], ">") ? 0 : 1);' "$image" "$disk"; then
		echo "[core-sync] disk core $disk is current (image $image)"
		return 0
	fi
	echo "[core-sync] copying core $image over $disk"
	tar -C "$SRC" --exclude=./wp-content --exclude=./.htaccess -cf - . | tar -C "$DOCROOT" -xf - \
		|| { echo "[core-sync] copy failed"; return 0; }
	chown -R www-data:www-data "$DOCROOT/wp-admin" "$DOCROOT/wp-includes"
	find "$DOCROOT" -maxdepth 1 -type f -name '*.php' -exec chown www-data:www-data {} +
	echo "[core-sync] now $(core_version "$DOCROOT")"
	timeout 120 wp --allow-root --path="$DOCROOT" core update-db 2>&1 | sed 's/^/[core-sync] /'
}

if [ "${1:-}" = "apache2-foreground" ]; then
	sync_core
	chown www-data:www-data "$DOCROOT" 2>/dev/null || true
	if [ "${MIIVO_AUDIT:-1}" = "1" ]; then
		(sleep 20 && /usr/local/bin/miivo-audit.sh) &
	fi
fi
exec docker-entrypoint.sh "$@"
