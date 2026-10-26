#!/bin/bash
# starts the read-only disk audit in the background once apache is up, then
# hands off to the stock entrypoint. one-off jobs pass their own command, so
# the audit only runs for the web server.
if [ "$1" = "apache2-foreground" ] && [ "${MIIVO_AUDIT:-1}" = "1" ]; then
	(sleep 20 && /usr/local/bin/miivo-audit.sh) &
fi
exec docker-entrypoint.sh "$@"
