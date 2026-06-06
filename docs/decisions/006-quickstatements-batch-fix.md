# ADR 006 — QuickStatements batch processing fix for self-hosted deployment

**Status:** Accepted  
**Date:** May 2026

## Context

After deploying `wikibase/quickstatements:1`, four issues were observed:

1. Interactive ("Run") imports worked correctly.
2. Batch mode ("Run in background") showed a progress bar stuck at 0% indefinitely.
3. The batch list page (`/#/batches/username`) never loaded — the browser repeated
   calls to `api.php?action=get_batches_info` every 5 seconds with no response.
4. After fixes 1–3, batches progressed but every command failed with
   "Item Qxxx is not available" even though the Wikibase API was reachable.

HAR analysis of the failing requests revealed a PHP fatal error returned as HTTP 200:

```
Fatal error: Uncaught Error: Class "mysqli" not found
in ToolforgeCommon.php:212
```

Deeper investigation revealed four compounding problems in the upstream image.

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

## Problem 4 — magnustools curl_multi sends no User-Agent header

Batches can fail with "Item Qxxx is not available" even though the Wikibase API
is reachable. Investigation shows:

- `getMultipleURLsInParallel()` in `magnustools/public_html/php/wikidata.php`
  uses `curl_multi` to fetch Wikibase items via the API.
- PHP's curl extension sends no User-Agent header by default. The php.ini
  `user_agent` setting is ignored by the curl extension — it only affects
  stream-based functions like `file_get_contents()`.
- Anubis (the bot protection layer in front of Apache) blocks requests with
  no User-Agent, returning an HTML challenge page instead of JSON.
- `loadItems()` receives HTML, `json_decode()` returns null, `hasItem()` returns
  false, and `bot.php` reports "Item Qxxx is not available" on every command.

The fix is to patch `wikidata.php` at build time using `sed` to add
`CURLOPT_USERAGENT` to each curl handle inside `getMultipleURLsInParallel()`.

This problem only manifests when the Wikibase API is protected by a User-Agent
filter such as Anubis. Deployments without such a filter are unaffected.

---

## Schema compatibility fixes

The upstream `schema.sql` contains two issues incompatible with MariaDB 11+:

1. **Prefix index on `int` column** (`KEY user (user(191))`) — rejected by MariaDB
   11. Fixed by removing the prefix length: `KEY user (user)`.
2. **Empty string default on `int` column** (`user int NOT NULL DEFAULT ''`) —
   rejected in strict mode. Fixed: `DEFAULT 0`.

The corrected schema must be applied manually to both QS databases before first
start. `ToolforgeCommon` derives a second DB name from the first by replacing
`_p` with `_auth` (`qsbot__quickstatements_p` → `qsbot__quickstatements_auth`).
Both databases need identical schemas.

See [docs/quickstatements-database-setup.md](../quickstatements-database-setup.md)
for the full step-by-step procedure including MariaDB bind address configuration,
firewall rules, database creation, and schema initialisation.

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

### Fix 4 — Patch magnustools to send a User-Agent in curl_multi requests

```dockerfile
RUN sed -i \
  's|curl_setopt(\$ch\[$key\], CURLOPT_SSL_VERIFYHOST, false);|curl_setopt($ch[$key], CURLOPT_SSL_VERIFYHOST, false);\n                                curl_setopt($ch[$key], CURLOPT_USERAGENT, '"'"'QuickStatements/1.0 (self-hosted bot)'"'"');|' \
  /var/www/html/magnustools/public_html/php/wikidata.php
```

This inserts `CURLOPT_USERAGENT` immediately after `CURLOPT_SSL_VERIFYHOST` —
the only place where curl handle options are set for each URL in the batch.
The patch applies to the image at build time; no upstream files are modified
in the repo.

The User-Agent string `QuickStatements/1.0 (self-hosted bot)` is intentionally
generic — it accurately identifies any deployment of this stack without requiring
site-specific customisation.

---

## Host-side infrastructure requirements

See [docs/quickstatements-database-setup.md](../quickstatements-database-setup.md)
for the complete host-side setup procedure. The requirements in summary:

- MariaDB must listen on both `127.0.0.1` and `172.18.0.1` (Docker bridge gateway)
- UFW must allow `172.18.0.0/16` → port 3306
- Two databases must exist: `qsbot__quickstatements_p` and `qsbot__quickstatements_auth`
- Both databases must have the corrected schema applied (MariaDB 11+ compatible)
- A MariaDB user must have `GRANT ALL` on both databases from the `172.18.0.%` host pattern
- Docker Compose network must be pinned to subnet `172.18.0.0/16`

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

1. **IPv4/IPv6 mismatch:** Docker containers have IPv4 only by default. If the
   Wikibase host blocks or does not respond to IPv4 connections from the
   QuickStatements host (e.g. due to firewall rules that only permit IPv6 for
   that source), batch item fetches will fail with "Item Qxxx is not available".
   Verify that the QuickStatements host can reach the Wikibase API over IPv4
   before troubleshooting elsewhere.

2. **Bot filtering (User-Agent):** Even when both services run on the same host,
   if your Wikibase instance is protected by a bot filter such as Anubis, the
   filter will block `curl_multi` requests that carry no User-Agent header.
   Fix 4 above addresses this by patching `wikidata.php` at build time.
   Do not rely on the php.ini `user_agent` setting — the curl extension ignores it.

---

## Files changed

| File | Change |
|---|---|
| `Dockerfile.quickstatements` | New — adds `mysqli`, cron runner, credentials entrypoint, User-Agent patch |
| `config/quickstatements-entrypoint.sh` | New — wrapper entrypoint |
| `config/quickstatements-replica.my.cnf` | New — DB credentials template |
| `docker-compose.yml` | `image:` → `build:`, `extra_hosts`, new volumes, new env vars, pinned subnet |
| `.env` / `template.env` | Added `QS_DB_USER`, `QS_DB_PASSWORD` |
| `docs/quickstatements-database-setup.md` | New — host-side database setup guide |
| `docs/decisions/006-quickstatements-batch-fix.md` | This file |

---

## Consequences

- Batch list loads correctly and batches are tracked in the database.
- Batch execution works correctly when QuickStatements and Wikibase run on the
  same host.
- Batch processing works correctly behind Anubis bot protection — the patched
  `wikidata.php` sends a `QuickStatements/1.0 (self-hosted bot)` User-Agent
  on all curl_multi API requests.
- The custom image must be rebuilt (`docker compose build quickstatements`) when
  the upstream image is updated.
- Credentials are injected at startup via `envsubst` — never stored in the image.
- Check `/var/log/quickstatements/bot.log` inside the container for batch runner
  errors.
- Check the `qsbot__quickstatements_p.batch` table for batch status
  (`INIT` / `RUN` / `DONE` / `ERROR`).