#!/usr/bin/env bash
# quickstatements-entrypoint.sh
#
# Wrapper around the upstream entrypoint.
# 1. Substitutes credentials into replica.my.cnf
# 2. Starts the cron daemon (for bot.php batch runner)
# 3. Hands off to the upstream entrypoint (starts Apache)

set -e

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

# Start cron daemon in the background so bot.php runs every minute
service cron start

# Hand off to the upstream entrypoint, which handles oauth.ini,
# config.json, php.ini, and then starts apache
exec /entrypoint.sh "$@"