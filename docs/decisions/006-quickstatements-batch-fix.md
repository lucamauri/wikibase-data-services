# ADR 006 — QuickStatements batch processing fix for self-hosted deployment

**Status:** Accepted  
**Date:** May 2026

## Context

After deploying `wikibase/quickstatements:1`, two issues were observed:

1. Interactive ("Run") imports worked correctly.
2. Batch mode ("Run in background") showed a progress bar stuck at 0% indefinitely.
3. The batch list page (`/#/batches/username`) never loaded — the browser repeated
   calls to `api.php?action=get_batches_info` every 5 seconds with no response.

HAR analysis of the failing requests revealed a PHP fatal error returned as HTTP 200:

```
Fatal error: Uncaught Error: Class "mysqli" not found
in ToolforgeCommon.php:212
```

Deeper investigation revealed three compounding problems in the upstream image.

---

## Problem 1 — `mysqli` PHP extension missing

The `wikibase/quickstatements:1` image ships PHP 8.3 on Debian 12 (bookworm) but
without the `mysqli` extension compiled in. QuickStatements uses the `magnustools`
library (`ToolforgeCommon`) for all database access, which requires `mysqli` —
there is no SQLite fallback.

Interactive mode works because it executes Wikibase API commands directly without
touching the batch database. Batch mode always calls `getDB()` → crashes.

---

## Problem 2 — Upstream image assumes Wikimedia Toolforge infrastructure

The `magnustools` library reads database credentials from:

```
/data/project/{owner_of_php_scripts}/replica.my.cnf
```

This is a Wikimedia Toolforge convention. The file does not exist in the container
by default, and the upstream `entrypoint.sh` does not create it. Without it,
`getDB()` constructs a connection to `tools.db.svc.wikimedia.cloud` with null
credentials.

PHP scripts in the container are owned by `nobody` (uid 65534), so the expected
path is:

```
/data/project/nobody/replica.my.cnf
```

The `local=true` flag in `replica.my.cnf` would redirect to `127.0.0.1:3308`, but
this is not usable in Docker — it points to the container loopback, not the host.

Instead, `extra_hosts` in `docker-compose.yml` maps `tools.db.svc.wikimedia.cloud`
to `172.18.0.1` (Docker bridge gateway), and MariaDB on the host is configured to
listen on that interface. `ToolforgeCommon` then connects to the host without any
code changes.

---

## Problem 3 — No batch runner process

The batch bot (`bot.php`) is designed for Wikimedia's `jsub` job scheduler, which
does not exist in a self-hosted environment. Without it, batches stay in `INIT`
status indefinitely. The fix is to run `bot.php single_batch` every minute via
cron inside the container.

---

## Schema compatibility fixes

The upstream `schema.sql` contains two issues incompatible with MariaDB 11+:

1. **Prefix index on `int` column** (`KEY user (user(191))`) — rejected by MariaDB
   11. Fixed by removing the prefix length: `KEY user (user)`.
2. **Empty string default on `int` column** (`user int NOT NULL DEFAULT ''`) —
   rejected in strict mode. Fixed: `DEFAULT 0`.

The corrected schema must be applied manually to both QS databases before first
start. The `_auth` database: `ToolforgeCommon` derives a second DB name from the
first by replacing `_p` with `_auth`
(`qsbot__quickstatements_p` → `qsbot__quickstatements_auth`). Both databases need
identical schemas.

---

## Solution

Extended the upstream image with `Dockerfile.quickstatements`.

### Fix 1 — Add `mysqli`

```dockerfile
RUN docker-php-ext-install mysqli
```

### Fix 2 — Credentials via wrapper entrypoint

- `config/quickstatements-entrypoint.sh` runs `envsubst` on the `replica.my.cnf`
  template before Apache starts, writes the substituted file to
  `/data/project/nobody/replica.my.cnf`, and sets `root:www-data 640` permissions
  (Apache workers run as `www-data` and must be able to read it).
- `extra_hosts` in `docker-compose.yml` maps `tools.db.svc.wikimedia.cloud` →
  `172.18.0.1`.

### Fix 3 — Cron-based batch runner

```dockerfile
RUN apt-get update && apt-get install -y cron
RUN echo "* * * * * www-data /usr/local/bin/php \
    /var/www/html/quickstatements/bot.php single_batch \
    >> /var/log/quickstatements/bot.log 2>&1" \
    > /etc/cron.d/quickstatements-bot
```

Wrapper entrypoint starts cron before handing off to the upstream Apache entrypoint.

---

## Host-side infrastructure requirements

### MariaDB — bind address

MariaDB on the host must listen on the Docker bridge gateway (`172.18.0.1`) in
addition to `127.0.0.1`. Add to your MariaDB configuration:

```ini
[mysqld]
bind-address        = 127.0.0.1,172.18.0.1
skip-name-resolve
```

`skip-name-resolve` prevents DNS-based authentication mismatches when the
connecting IP resolves to an unexpected hostname.

### MariaDB — databases and user

```sql
CREATE DATABASE `qsbot__quickstatements_p`    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE `qsbot__quickstatements_auth`  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'qsbot'@'172.18.0.%' IDENTIFIED BY 'your_password';
CREATE USER 'qsbot'@'localhost'   IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_p`.*    TO 'qsbot'@'172.18.0.%';
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_auth`.* TO 'qsbot'@'172.18.0.%';
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_p`.*    TO 'qsbot'@'localhost';
```

### Firewall

Allow the Docker bridge network to reach host MariaDB. Example for UFW:

```
# /etc/ufw/before.rules
-A ufw-before-input -s 172.18.0.0/16 -p tcp --dport 3306 -j ACCEPT
```

Using the subnet (`172.18.0.0/16`) rather than the bridge interface name
ensures the rule survives interface renames after stack recreation.

### docker-compose.yml — pinned subnet

```yaml
networks:
  default:
    ipam:
      config:
        - subnet: 172.18.0.0/16
```

Pinning the subnet ensures the gateway address stays `172.18.0.1` after stack
recreation. Without this, Docker may assign a different subnet and the firewall
rule and MariaDB bind address would no longer match.

---

## Cross-server deployments

If QuickStatements runs on a different host than your Wikibase instance, batch
execution requires the QuickStatements container to reach the Wikibase API to
fetch item data during batch processing.

Two potential blockers to be aware of:

1. **Bot filtering:** If your Wikibase host runs a bot protection layer (such as
   Anubis), add an allow rule for the IP address of the QuickStatements host.
   Batch processing sends requests with a non-browser User-Agent that bot filters
   may block.

2. **IPv4/IPv6 mismatch:** Docker containers have IPv4 only by default. If the
   Wikibase host blocks or does not respond to IPv4 connections from the
   QuickStatements host (e.g. due to firewall rules that only permit IPv6 for
   that source), batch item fetches will fail with "Item Qxxx is not available".
   Verify that the QuickStatements host can reach the Wikibase API over IPv4
   before troubleshooting elsewhere.

These issues resolve automatically when both services run on the same host —
the item fetch becomes a local call through the Docker bridge.

---

## Files changed

| File | Change |
|---|---|
| `Dockerfile.quickstatements` | New — custom image build |
| `config/quickstatements-entrypoint.sh` | New — wrapper entrypoint |
| `config/quickstatements-replica.my.cnf` | New — DB credentials template |
| `docker-compose.yml` | `image:` → `build:`, `extra_hosts`, new volumes, new env vars, pinned subnet |
| `.env` / `template.env` | Added `QS_DB_USER`, `QS_DB_PASSWORD` |
| `docs/decisions/006-quickstatements-batch-fix.md` | This file |

---

## Consequences

- Batch list loads correctly and batches are tracked in the database.
- Batch execution works correctly when QuickStatements and Wikibase run on the
  same host.
- The custom image must be rebuilt (`docker compose build quickstatements`) when
  the upstream image is updated.
- Credentials are injected at startup via `envsubst` — never stored in the image.
- Check `/var/log/quickstatements/bot.log` inside the container for batch runner
  errors.
- Check the `qsbot__quickstatements_p.batch` table for batch status
  (`INIT` / `RUN` / `DONE` / `ERROR`).