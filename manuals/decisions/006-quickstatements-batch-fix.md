# ADR 006 — QuickStatements batch processing fix for self-hosted deployment

**Status:** Accepted
**Date:** May 2026 (Fix 6 added July 2026)

## Context

After deploying `wikibase/quickstatements:1`, five issues were observed:

1. Interactive ("Run") imports worked correctly.
2. Batch mode ("Run in background") showed a progress bar stuck at 0% indefinitely.
3. The batch list page (`/#/batches/username`) never loaded — the browser repeated
   calls to `api.php?action=get_batches_info` every 5 seconds with no response.
4. After fixes 1–3, batches progressed but every command failed with
   "Item Qxxx is not available" even though the Wikibase API was reachable.
5. After fixes 1–4, batch execution worked but the batch detail page
   (`/#/batch/N`) was blank — commands were stored in the database but never
   displayed in the browser.

HAR analysis of the failing requests for issues 1–4 revealed a PHP fatal error
returned as HTTP 200:

```
Fatal error: Uncaught Error: Class "mysqli" not found
in ToolforgeCommon.php:212
```

Deeper investigation revealed five compounding problems in the upstream image
and configuration. A sixth, unrelated cosmetic issue — a hardcoded Wikimedia
Toolforge logo in the UI — was addressed separately (see Fix 6 below).

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

After DataTrek migrated to `unitedwikitrek` (same host as QuickStatements),
batches still failed with "Item Qxxx is not available". Investigation showed:

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

---

## Problem 5 — Site name case mismatch causes blank batch detail page

After all four fixes above, batch execution worked correctly but navigating to
a batch detail page (`/#/batch/N`) showed a blank page with no commands listed,
even though the commands were present in the database.

HAR analysis showed that `api.php?action=get_commands_from_batch` was never
called by the browser. The call sequence stopped after `get_batch_info`.

Root cause: a case mismatch between the site identifier stored in the database
and the key used in `config.json`.

The QuickStatements `api.php` lowercases the site name with `strtolower()` before
writing it to the `batch` table:

```php
$site = strtolower ( trim ( get_request ( 'site' , '' ) ) ) ;
```

So batches are stored with `site=wikitrek` (lowercase). However, `config.json`
was generated from a template where `${SITENAME}` expanded to `WikiTrek`
(preserving the case of `WIKIBASE_NAME` in `.env`). The result was a `config.json`
with `"sites": {"WikiTrek": {...}}`.

In the browser, when the Vue batch detail component tried to look up
`config.sites[meta.batch.site]`, it evaluated `config.sites["wikitrek"]` —
which is `undefined` because the key is `"WikiTrek"`. JavaScript threw a silent
`TypeError` (cannot read property of undefined), Vue caught it internally, and
the `batch-commands` component never mounted. No API call was made; no error
was shown.

The fix requires the site identifier in `config.json` to be lowercase, matching
what `api.php` stores in the database. This fix has no Dockerfile component —
it is implemented entirely in `quickstatements-entrypoint.sh` and
`config/quickstatements-config.json` (see Solution, Fix 5, below).

---

## Problem 6 — Hardcoded Wikimedia Toolforge logo (cosmetic, unrelated to batch processing)

Independently of the batch-processing problems above, the QuickStatements UI
displays a Wikimedia Toolforge badge in the top-right corner of every page.
For a self-hosted deployment with no relationship to Wikimedia Toolforge
infrastructure, this is misleading branding that operators reasonably want to
replace with their own logo.

### Why this isn't a simple file patch

The natural first assumption is that the navbar markup is a local file inside
the image that can be patched with `sed`, the same way Fix 4 patches
`wikidata.php`. This assumption is wrong, and the investigation to discover why
is worth documenting so future maintainers don't repeat it.

`vue.js` (served locally from `quickstatements/public_html/vue.js`) calls:

```js
vue_components.loadComponents(['wd-date', 'wd-link', 'tool-translate',
                                'tool-navbar', 'commons-thumbnail', ...]);
```

`shared.js` — itself fetched live from Wikimedia's CDN at
`https://tools-static.wmflabs.org/magnustools/resources/vue/shared.js`, not
from any local file — defines how bare component names in that array are
resolved:

```js
components_base_url : 'https://tools-static.wmflabs.org/magnustools/resources/vue/',
// ...
return /^(http:|https:|\/|\.)/.test(component) || /\.html$/.test(component)
  ? component
  : this.components_base_url + component + '.html';
```

Since `'tool-navbar'` is a bare name (no leading `http:`, `/`, `.`, and no
`.html` suffix), it resolves to
`https://tools-static.wmflabs.org/magnustools/resources/vue/tool-navbar.html`
— fetched directly from Wikimedia's CDN, entirely in the browser, bypassing
our container completely.

A copy of `tool-navbar.html` does exist inside the image, at
`/var/www/html/magnustools/public_html/resources/vue/tool-navbar.html` (the
`magnustools` library ships it as source, presumably for reference or
Toolforge-hosted use). However, **Apache's `DocumentRoot` is
`/var/www/html/quickstatements/public_html`**, with no `Alias` exposing the
`magnustools` directory under any URL. That file is never reachable over HTTP
and patching it in place has no effect — the browser never requests it.

### The fix

1. **Ship a local replacement component**
   (`config/quickstatements-tool-navbar.html`) — an exact copy of the upstream
   markup (as fetched from the CDN), with only the `<img src>` attribute
   changed to a `${QS_LOGO_URL}` placeholder. All other markup (the Bootstrap
   navbar structure, the `tt`/translate widget hook, the `Vue.component`
   registration) is preserved unchanged, since it was already confirmed
   working and understanding an unfamiliar Vue component's full contract well
   enough to safely simplify it was judged not worth the risk.

2. **Copy it into the served directory at build time**, so it's reachable at
   `resources/vue/tool-navbar.html` under the existing `DocumentRoot` — no new
   Apache `Alias` needed.

3. **Patch `vue.js`** so the `loadComponents([...])` array entry changes from
   the bare name `'tool-navbar'` to the local, `.html`-suffixed path
   `'resources/vue/tool-navbar.html'`. Per `shared.js`'s own resolution logic,
   any entry already ending in `.html` is used as a literal path, bypassing
   `components_base_url` (the CDN) entirely. This affects **only** the
   `tool-navbar` entry — all other CDN-served components in the same array
   (`wd-date`, `wd-link`, `tool-translate`, `commons-thumbnail`) are
   unaffected and continue loading from Wikimedia exactly as before.

4. **Resolve the actual logo URL at container startup**, via the wrapper
   entrypoint, using a hybrid fallback: an optional `QUICKSTATEMENTS_LOGO`
   `.env` variable, falling back to the already-existing `WIKIBASE_LOGO`
   variable (used for WDQS Frontend branding) if unset. This means no new
   required configuration for operators who are happy showing the same logo
   in both places, while still allowing a different icon here if desired.

### Why `QS_LOGO_URL` as an internal name, not `QUICKSTATEMENTS_LOGO` directly

The placeholder embedded in `config/quickstatements-tool-navbar.html` is
`${QS_LOGO_URL}`, not `${QUICKSTATEMENTS_LOGO}` or `${WIKIBASE_LOGO}` directly.
The fallback decision (`QUICKSTATEMENTS_LOGO` if set, else `WIKIBASE_LOGO`) is
resolved once, in `quickstatements-entrypoint.sh`, and exported as
`QS_LOGO_URL`. This keeps the fallback logic in a single place rather than
duplicated, and mirrors the existing pattern used for `QS_SITE_ID` (Fix 5) —
an internal, entrypoint-resolved name, distinct from the operator-facing
`.env` variables that feed it.

### Why the `href="/"` target on the icon was left unchanged

The icon's hyperlink (`href="/"`, linking to the QuickStatements root) was
deliberately left as-is rather than repointed to the Wikibase instance itself.
This was a smaller, more conservative change: it avoids altering existing
navigation behavior, and the actual problem being solved — misleading
Wikimedia branding — is fully addressed by the logo image swap alone.

### Why `tt_title="wmf_powered"` was left unchanged

This attribute is consumed by the `tt` (tool-translate) widget, which looks up
its value as a translation key against Wikimedia's translation service to
produce (most likely) a hover tooltip. Renaming it to something
deployment-specific (e.g. a key derived from `WIKIBASE_NAME`) would almost
certainly resolve to a translation key that doesn't exist upstream, likely
producing missing or broken tooltip text — a worse regression than the
original, cosmetic-only branding issue. It was left unchanged as out of scope
for this fix; if the tooltip text itself is a problem, removing the attribute
entirely (not renaming it) would be the safer follow-up.

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

### Fix 5 — Lowercase site identifier for config.json

The site identifier used as a key in `config.json` must be lowercase to match
what `api.php` stores in the database via `strtolower()`.

`WIKIBASE_NAME` in `.env` carries the display name (`WikiTrek`) and must not be
changed — it is used in the OAuth agent string and WDQS frontend branding. A
separate lowercase identifier is derived at container startup instead.

`config/quickstatements-entrypoint.sh` derives `QS_SITE_ID` from `SITENAME`
using bash parameter expansion before the upstream entrypoint runs `envsubst`:

```bash
export QS_SITE_ID="${SITENAME,,}"
```

`config/quickstatements-config.json` uses `${QS_SITE_ID}` for all three
identifier fields (`"site"`, the sites object key, and `"project"`), while
`config/quickstatements-oauth.ini` continues to use `${SITENAME}` for the
human-readable `agent` string.

The upstream `/entrypoint.sh` runs `envsubst` on the config template with the
full environment, so `QS_SITE_ID` is available without any further changes.

**Why not just lowercase `WIKIBASE_NAME` in `.env`?** That would break the
OAuth agent string (`WikiTrek Docker QuickStatements` would become
`wikitrek docker quickstatements`) and the WDQS frontend title. The two
concerns — display name and database identifier — must be kept separate.

**Why not a new `.env` variable?** Adding `QS_SITENAME=wikitrek` to `.env`
would require operators to keep it in sync with `WIKIBASE_NAME` manually.
Deriving it automatically in the entrypoint eliminates that risk entirely.

### Fix 6 — Configurable logo, replacing the hardcoded Toolforge branding

```dockerfile
# Part 1 — copy our patched local component into the served directory.
COPY config/quickstatements-tool-navbar.html \
     /var/www/html/quickstatements/public_html/resources/vue/tool-navbar.html

# Part 2 — redirect the 'tool-navbar' component lookup to our local file.
RUN sed -i \
  "s|'tool-navbar'|'resources/vue/tool-navbar.html'|" \
  /var/www/html/quickstatements/public_html/vue.js
```

`config/quickstatements-entrypoint.sh` resolves the fallback and runs
`envsubst` on the copied file at container startup:

```bash
export QS_LOGO_URL="${QUICKSTATEMENTS_LOGO:-$WIKIBASE_LOGO}"
# ...
envsubst '${QS_LOGO_URL}' \
    < /var/www/html/quickstatements/public_html/resources/vue/tool-navbar.html \
    > /tmp/tool-navbar.html \
    && mv /tmp/tool-navbar.html /var/www/html/quickstatements/public_html/resources/vue/tool-navbar.html
```

See Problem 6 above for the full investigation and reasoning, including why an
earlier attempt to `sed`-patch the upstream `magnustools` copy of this file
had no effect (that file is never served — see Problem 6 for details).

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

These issues resolve automatically when both services run on the same host,
provided Fix 4 is applied to handle the Anubis User-Agent requirement.

---

## Files changed

| File | Change |
|---|---|
| `Dockerfile.quickstatements` | New — adds `mysqli`, cron runner, credentials entrypoint, User-Agent patch, logo branding (Fix 6) |
| `config/quickstatements-entrypoint.sh` | New — substitutes DB credentials, starts cron, derives `QS_SITE_ID`, resolves and substitutes `QS_LOGO_URL` |
| `config/quickstatements-replica.my.cnf` | New — DB credentials template |
| `config/quickstatements-config.json` | Updated — `${SITENAME}` → `${QS_SITE_ID}` for all identifier fields |
| `config/quickstatements-tool-navbar.html` | New — local replacement for the CDN-fetched navbar component, with `${QS_LOGO_URL}` placeholder |
| `docker-compose.yml` | `image:` → `build:`, `extra_hosts`, new volumes, env vars (including `WIKIBASE_LOGO`, `QUICKSTATEMENTS_LOGO`), pinned subnet |
| `template.env` | Added `QS_DB_USER`, `QS_DB_PASSWORD`, `QUICKSTATEMENTS_LOGO` |
| `docs/decisions/006-quickstatements-batch-fix.md` | This file |

---

## Consequences

- Batch list loads correctly and batches are tracked in the database.
- Batch execution works correctly when QuickStatements and Wikibase run on the
  same host.
- Batch detail pages load correctly — commands are displayed with their status,
  message, and timestamp.
- Batch processing works correctly behind Anubis bot protection — the patched
  `wikidata.php` sends a `QuickStatements/1.0 (self-hosted bot)`
  User-Agent on all curl_multi API requests.
- The top-right branding icon shows an operator-configurable logo instead of
  the Wikimedia Toolforge badge, defaulting to `WIKIBASE_LOGO` if
  `QUICKSTATEMENTS_LOGO` is not set. All other CDN-served UI components
  (`wd-date`, `wd-link`, `tool-translate`, `commons-thumbnail`) are unaffected
  and continue to load from Wikimedia's CDN as before.
- The custom image must be rebuilt (`docker compose build quickstatements`) when
  the upstream image is updated. Note in particular that Fix 6 depends on the
  current structure of `vue.js`'s `loadComponents([...])` array and of the
  upstream `tool-navbar.html` markup — if a future upstream QuickStatements
  release changes either, this fix should be re-verified against the new
  version rather than assumed to still apply cleanly.
- Credentials are injected at startup via `envsubst` — never stored in the image.
- Check `/var/log/quickstatements/bot.log` inside the container for batch runner
  errors.
- Check the `qsbot__quickstatements_p.batch` table for batch status
  (`INIT` / `RUN` / `DONE` / `ERROR`).