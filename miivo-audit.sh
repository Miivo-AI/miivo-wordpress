#!/bin/bash
# read-only incident audit of the render disk (wp2shell, 2026-09-05). prints to
# stdout with an [audit] prefix so the result lands in the render logs. it
# changes nothing; secrets in wp-config.php are redacted before printing.
cd /var/www/html || exit 0
WP="wp --allow-root --path=/var/www/html --skip-plugins --skip-themes"
SHELL_DIR=wp-content/plugins/wp-optimizer-797ae4e7ad

{
	echo "== core version"
	grep "wp_version =" wp-includes/version.php

	echo "== owners and modes"
	stat -c '%U:%G %a %n' . wp-admin wp-includes wp-content wp-content/plugins wp-content/uploads wp-config.php index.php

	echo "== core checksums"
	timeout 180 $WP core verify-checksums 2>&1 | tail -80

	echo "== plugin checksums"
	timeout 240 $WP plugin verify-checksums --all 2>&1 | tail -80

	echo "== plugins"
	ls -la --time-style=long-iso wp-content/plugins

	echo "== mu-plugins"
	ls -la --time-style=long-iso wp-content/mu-plugins 2>&1

	echo "== drop-ins (wp-content/*.php)"
	ls -la --time-style=long-iso wp-content/*.php 2>&1

	echo "== themes"
	ls -la --time-style=long-iso wp-content/themes

	echo "== docroot"
	ls -la --time-style=long-iso /var/www/html

	echo "== executable or config files in uploads"
	find wp-content/uploads -type f \( -iname '*.php*' -o -iname '*.phtml' -o -iname '*.phar' -o -iname '*.pht' -o -name '.htaccess' -o -name '.user.ini' \) 2>/dev/null | head -50

	echo "== .htaccess and .user.ini outside uploads"
	find . \( -name '.htaccess' -o -name '.user.ini' \) ! -path './wp-content/uploads/*' 2>/dev/null | head -30

	echo "== files changed since 2026-09-04 outside uploads"
	find . -type f -newermt '2026-09-04' ! -path './wp-content/uploads/*' ! -path './wp-content/cache/*' \
		-printf '%TY-%Tm-%Td %TH:%TM %u %p\n' 2>/dev/null | sort | head -200

	echo "== temp-write-test files"
	find . -name 'temp-write-test-*' 2>/dev/null | head -20

	echo "== webshell plugin"
	ls -la --time-style=full-iso "$SHELL_DIR" 2>&1
	sha1sum "$SHELL_DIR"/* 2>&1
	head -40 "$SHELL_DIR"/*.php 2>&1

	echo "== suspicious php patterns outside uploads"
	grep -rlE --include='*.php' \
		'passthru\(base64_decode|eval\(base64_decode|eval\(gzinflate|eval\(str_rot13|assert\(\$_|shell_exec\(\$_|system\(\$_|register_rest_route\([^)]*__return_true' \
		wp-content 2>/dev/null | grep -v '/uploads/' | head -40

	echo "== wp-config.php structure (secrets redacted)"
	sed -E \
		-e "s/(define\(\s*['\"][A-Z_]*(KEY|SALT|PASSWORD)['\"]\s*,\s*).*/\1<redacted>/I" \
		-e "s/'[^']{24,}'/'<redacted>'/g" \
		wp-config.php | grep -vE '^\s*(\*|//|/\*|$)' | head -80

	echo "== done"
} 2>&1 | sed -u 's/^/[audit] /'
