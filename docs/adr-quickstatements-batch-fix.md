# ADR: QuickStatements Batch Processing Fix for Self-Hosted Deployment

**Date:** May 2026  
**Status:** Accepted — implemented on `unitedwikitrek`  
**Repo:** `wikibase-data-services`

---

## Context

After deploying `wikibase/quickstatements:1` on `unitedwikitrek`, two issues were observed:

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

The `wikibase/quickstatements:1` image ships PHP 8.3.8 on Debian 12 (bookworm) but
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
`getDB()` constructs a connection to `tools.db.svc.wikimedia.cloud` with null credentials.

PHP scripts in the container are owned by `nobody` (uid 65534), so the expected path is:
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

The upstream `schema.sql` contains two issues incompatible with MariaDB 11.8:

1. **Prefix index on `int` column** (`KEY user (user(191))`) — rejected by MariaDB 11.8.
   Fixed by removing the prefix length: `KEY user (user)`.
2. **Empty string default on `int` column** (`user int NOT NULL DEFAULT ''`) — rejected
   in strict mode. Fixed: `DEFAULT 0`.

The corrected schema was applied manually to both QS databases.

The `_auth` database: `ToolforgeCommon` derives a second DB name from the first
by replacing `_p` with `_auth` (`qsbot__quickstatements_p` → `qsbot__quickstatements_auth`).
This is a Toolforge naming convention — both databases need identical schemas.

---

## Solution

Extended the upstream image with `Dockerfile.quickstatements`:

### Fix 1 — Add `mysqli`

```dockerfile
RUN docker-php-ext-install mysqli
```

### Fix 2 — Credentials via wrapper entrypoint

- `config/quickstatements-entrypoint.sh` runs `envsubst` on `replica.my.cnf`
  template before Apache starts, writes the substituted file to
  `/data/project/nobody/replica.my.cnf`, and sets `root:www-data 640` permissions
  (Apache workers run as `www-data` and must be able to read it).
- `extra_hosts` maps `tools.db.svc.wikimedia.cloud → 172.18.0.1`.

### Fix 3 — Cron-based batch runner

```dockerfile
RUN apt-get update && apt-get install -y cron
RUN echo "* * * * * www-data /usr/local/bin/php \
    /var/www/html/quickstatements/bot.php single_batch \
    >> /var/log/quickstatements/bot.log 2>&1" \
    > /etc/cron.d/quickstatements-bot
```

Wrapper entrypoint starts cron before handing off to Apache.

---

## Infrastructure changes on `unitedwikitrek`

### `/etc/mysql/mariadb.conf.d/70-docker.cnf`

```ini
[mysqld]
bind-address        = 127.0.0.1,172.18.0.1
skip-name-resolve
```

`skip-name-resolve` prevents DNS-based auth mismatches (connecting IP was resolving
to the server's public reverse DNS instead of the bridge IP).

### MariaDB databases and user

```sql
CREATE DATABASE `qsbot__quickstatements_p`   CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE `qsbot__quickstatements_auth` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'qsbot'@'172.18.0.%' IDENTIFIED BY '...';
CREATE USER 'qsbot'@'localhost'   IDENTIFIED BY '...';
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_p`.*    TO 'qsbot'@'172.18.0.%';
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_auth`.* TO 'qsbot'@'172.18.0.%';
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_p`.*    TO 'qsbot'@'localhost';
```

### `/etc/ufw/before.rules`

```
# Allow Docker bridge network (wikibase-data-services) to reach host MariaDB
-A ufw-before-input -s 172.18.0.0/16 -p tcp --dport 3306 -j ACCEPT
```

Rule uses subnet (`172.18.0.0/16`), not bridge interface name, for stability.

### `docker-compose.yml` — pinned subnet

```yaml
networks:
  default:
    ipam:
      config:
        - subnet: 172.18.0.0/16
```

Pins the Docker network subnet so the gateway stays `172.18.0.1` after stack recreation.

---

## Changes on `wikitrek143` (partial — cross-server limitation)

While DataTrek remains on `wikitrek143`, QuickStatements needs to fetch items from
`data.wikitrek.org` API during batch execution. Two blocking layers were found and
partially fixed:

### `/etc/anubis/botpolicy.yaml`

Added as first rule:
```yaml
- name: allow-unitedwikitrek
  remote_addresses:
    - "138.199.158.19/32"
  action: ALLOW
```

### `/etc/apache2/conf-available/block_bots.conf`

The blank User-Agent rule was updated to whitelist `unitedwikitrek`:
```apache
<If "(%{HTTP_USER_AGENT} == '-' || %{HTTP_USER_AGENT} == '')
    && %{REMOTE_ADDR} != '::1'
    && %{REMOTE_ADDR} != '127.0.0.1'
    && %{REMOTE_ADDR} != '138.199.158.19'">
    Require all denied
</If>
```

> ⚠️ **Remaining issue:** Despite these fixes, batch commands still fail with
> "Item Qxxx is not available" because `wikitrek143` refuses IPv4 connections from
> `138.199.158.19` at the network level (not UFW — cause not investigated further).
> The container has no IPv6, so it cannot use the IPv6 path that works.
>
> **This will resolve automatically when DataTrek migrates to `unitedwikitrek`.**
> The item fetch will then be a local call (`172.18.0.1` → Apache on same host).
> Do not spend time on this cross-server issue.

---

## Files changed in `wikibase-data-services` repo

| File | Change |
|---|---|
| `Dockerfile.quickstatements` | New — custom image build |
| `config/quickstatements-entrypoint.sh` | New — wrapper entrypoint |
| `config/quickstatements-replica.my.cnf` | New — DB credentials template |
| `docker-compose.yml` | `image:` → `build:`, `extra_hosts`, new volume, new env vars, pinned subnet |
| `.env` | Added `QS_DB_USER`, `QS_DB_PASSWORD` |
| `docs/adr-quickstatements-batch-fix.md` | This file |

---

## Consequences

- Batch list loads correctly and batches are created and tracked in the database.
- Batch execution works for items on the same server; fails for cross-server item
  fetch until DataTrek migrates to `unitedwikitrek`.
- The custom image must be rebuilt (`docker compose build quickstatements`) when
  the upstream image is updated.
- Credentials are injected at startup via `envsubst` — never stored in the image.
- Check `/var/log/quickstatements/bot.log` inside the container for batch runner errors.
- Check `qsbot__quickstatements_p.batch` table for batch status (`INIT`/`RUN`/`DONE`/`ERROR`).