#!/usr/bin/env bash
# quickstatements-entrypoint.sh
#
# Wrapper around the upstream entrypoint.
# 1. Substitutes credentials into replica.my.cnf
# 2. Resolves and substitutes the QuickStatements logo (Fix 6)
# 3. Starts the cron daemon (for bot.php batch runner)
# 4. Hands off to the upstream entrypoint (starts Apache)

set -e

# Derive lowercase site identifier from SITENAME.
# QuickStatements stores site names in lowercase (strtolower) in the database.
# QS_SITE_ID must match that so config.json keys align with the batch table,
# preventing a silent JS crash on the batch detail page when
# config.sites[site] is undefined in the browser.
export QS_SITE_ID="${SITENAME,,}"

# Fix 6 — resolve the QuickStatements logo URL.
# QUICKSTATEMENTS_LOGO is optional. If the operator hasn't set it in .env,
# fall back to WIKIBASE_LOGO (already used for WDQS frontend branding),
# so no extra configuration is required for a sensible default.
#
# Bash parameter expansion ${VAR:-default} is used here (not ${VAR,,}-style
# case conversion) because it's a plain fallback-if-unset/empty check, which
# is portable even in Compose-interpolated contexts. This assignment happens
# in the entrypoint (not docker-compose.yml) because Compose V2 does not
# support this expansion form directly in environment: blocks.
export QS_LOGO_URL="${QUICKSTATEMENTS_LOGO:-$WIKIBASE_LOGO}"

# Create the target directory if it doesn't exist
mkdir -p /data/project/nobody
mkdir -p /var/log/quickstatements

# Substitute ${QS_DB_USER} and ${QS_DB_PASSWORD} from environment
envsubst '${QS_DB_USER} ${QS_DB_PASSWORD}' \
    < /templates/replica.my.cnf \
    > /data/project/nobody/replica.my.cnf

# Restrict permissions — readable only by root and www-data
chown root:www-data /data/project/nobody/replica.my.cnf
chmod 640 /data/project/nobody/replica.my.cnf

# CHANGED: Fix 6 — substitute ${QS_LOGO_URL} into our local tool-navbar.html.
#
# This file was COPY'd into the served QuickStatements directory at build
# time (see Dockerfile.quickstatements) — NOT the upstream magnustools path,
# which is never reachable via HTTP (no Apache Alias exposes it; DocumentRoot
# is /var/www/html/quickstatements/public_html only). vue.js was also patched
# at build time to fetch this local file instead of the Wikimedia CDN version
# (see Dockerfile.quickstatements, Fix 6, Part 2).
#
# We only substitute QS_LOGO_URL explicitly (not the full environment) to
# avoid accidentally mangling any other ${...} sequences that might appear
# elsewhere in the file (e.g. inside embedded Vue template expressions).
envsubst '${QS_LOGO_URL}' \
    < /var/www/html/quickstatements/public_html/resources/vue/tool-navbar.html \
    > /tmp/tool-navbar.html \
    && mv /tmp/tool-navbar.html /var/www/html/quickstatements/public_html/resources/vue/tool-navbar.html

# Start cron daemon in the background so bot.php runs every minute
service cron start

# Hand off to the upstream entrypoint, which handles oauth.ini,
# config.json, php.ini, and then starts apache
exec /entrypoint.sh "$@"