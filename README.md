# Wikibase Data Services

A Docker Compose stack providing auxiliary data services for an existing
[Wikibase](https://wikiba.se) installation running on a native LAMP stack.

This project is designed for deployments where MediaWiki, Wikibase, and
MariaDB run directly on the host — **not** in Docker. It provides only the
services that benefit from containerisation:

| Service | Purpose |
|---|---|
| **WDQS** (Blazegraph) | SPARQL query engine over your Wikibase data |
| **WDQS Updater** | Keeps Blazegraph in sync with Wikibase |
| **WDQS Frontend** | Browser-based SPARQL query editor |
| **Elasticsearch** | Full-text search for MediaWiki CirrusSearch |
| **QuickStatements** | Batch editing tool for Wikibase |
| **Traefik** | Internal HTTP router between containers |

> If you need a full self-hosted Wikibase stack including MediaWiki and
> MariaDB in Docker, see the official
> [Wikibase Suite Deploy](https://github.com/wmde/wikibase-release-pipeline/tree/main/deploy)
> by Wikimedia Germany.

---

## Requirements

- Docker 24.0 or later
- Docker Compose V2 (`docker compose`, not `docker-compose`)
- An existing Wikibase installation accessible via a public hostname
- A reverse proxy on the host (Apache, Nginx, Caddy…) to handle TLS and
  route traffic to Traefik — or set `TRAEFIK_BIND_ADDRESS=0.0.0.0` in
  `.env` for standalone use without a host reverse proxy

**RAM:** approximately 3 GB for the full stack (Blazegraph ~2 GB,
Elasticsearch ~512 MB, other services ~500 MB combined).

---

## Quick start

```bash
# 1. Clone the repository
git clone https://github.com/lucamauri/wikibase-data-services
cd wikibase-data-services

# 2. Create your configuration
cp template.env .env
nano .env   # fill in your values — see comments in the file

# 3. Start the stack
docker compose up -d

# 4. Check that all services are healthy
docker compose ps
```

`template.env` contains a description of every variable. The minimum
required variables are:

```env
WIKIBASE_SCHEME=https
WIKIBASE_HOST=data.example.org
WIKIBASE_API_PATH=/w/api.php
WDQS_FRONTEND_PUBLIC_HOST=query.example.org
QUICKSTATEMENTS_PUBLIC_HOST=qs.example.org
WIKIBASE_NAME=My Wikibase
WIKIBASE_LOGO=https://data.example.org/path/to/logo.svg
WIKIBASE_FAVICON=https://data.example.org/path/to/favicon.ico
WIKIBASE_COPYRIGHT=https://data.example.org/wiki/Project:About
WIKIBASE_EXAMPLES_PAGE=Help:SPARQL_query_examples
```

> **Note:** `WIKIBASE_CONCEPT_URI` is intentionally absent from `template.env`
> and must not be set manually. It is assembled automatically in
> `docker-compose.yml`. Setting it — especially with a `/entity/` suffix —
> causes `BadSubjectException` in the WDQS updater and silently breaks
> Blazegraph synchronisation. See
> [docs/decisions/005-concept-uri-assembly.md](docs/decisions/005-concept-uri-assembly.md)
> for the full explanation.

---

## Apache integration

Traefik listens on `127.0.0.1:8880` by default. Your host reverse proxy
must forward requests for `WDQS_FRONTEND_PUBLIC_HOST` and
`QUICKSTATEMENTS_PUBLIC_HOST` to that port, preserving the `Host` header.

Example Apache VirtualHost configurations are in
[docs/examples/apache/](docs/examples/apache/).

Critical rules that are easy to get wrong:

- `X-Real-IP` header must use a **capital P** — `X-Real-Ip` (lowercase)
  causes Anubis to fail silently with 15–30 second page loads for all users
- The internal `:8080` VirtualHost must bind to `[::1]:8080`, not `*:8080`
- `ServerName` is required on the `:8080` VirtualHost
- `ProxyPreserveHost On` is required so Traefik can route correctly

---

## Anubis integration

[Anubis](https://github.com/TecharoHQ/anubis) is an optional but recommended
bot protection layer that sits between Apache and the internal backend. It
filters automated traffic before it reaches your containers.

The traffic chain with Anubis:

```
Internet → Apache :443 (TLS) → Anubis :[::1]:8923 → Apache :[::1]:8080 → Traefik :8880 → container
```

Without Anubis, Apache proxies directly from `:443` to `:8080`. The
Apache VirtualHost examples in [docs/examples/apache/](docs/examples/apache/)
show both configurations.

---

## Data loading

On first deployment, Blazegraph starts empty. The WDQS updater only
processes changes that happen after it starts — it will not back-fill
your existing Wikibase data.

You must perform an initial load from a Wikibase RDF dump before starting
the full stack. See [docs/data-loading.md](docs/data-loading.md) for the
step-by-step procedure.

If you are migrating from an existing server, see
[docs/data-migration.md](docs/data-migration.md) instead.

---

## QuickStatements OAuth

QuickStatements requires an OAuth 1.0a consumer registered on your Wikibase
before users can log in. This is a one-time setup step.

See [docs/quickstatements-oauth-setup.md](docs/quickstatements-oauth-setup.md)
for the step-by-step registration and approval walkthrough.

---

## Elasticsearch and CirrusSearch

After starting the stack, connect MediaWiki to Elasticsearch by adding
to `LocalSettings.php`:

```php
wfLoadExtension( 'CirrusSearch' );
wfLoadExtension( 'Elastica' );
$wgSearchType = 'CirrusSearch';
$wgCirrusSearchServers = [ '127.0.0.1' ];
```

Then run the indexing scripts from your MediaWiki directory:

```bash
php maintenance/run.php updateSearchIndexConfig
php maintenance/run.php forceSearchIndex
```

See [docs/elasticsearch-setup.md](docs/elasticsearch-setup.md) for the
full setup guide, re-indexing instructions, and memory tuning.

---

## Troubleshooting

### `BadSubjectException` in WDQS updater logs

The updater logs are full of `BadSubjectException` errors and Blazegraph
has no data or stops updating.

**Cause:** `WIKIBASE_CONCEPT_URI` is set incorrectly — most commonly with
a `/entity/` suffix copied from Wikidata examples.

**Fix:** Remove `WIKIBASE_CONCEPT_URI` from `.env` entirely. It is
assembled automatically in `docker-compose.yml`. See
[docs/decisions/005-concept-uri-assembly.md](docs/decisions/005-concept-uri-assembly.md).

---

### `421 Misdirected Request` from WDQS frontend

The SPARQL query UI loads but queries return a 421 error.

**Cause:** The nginx config in `wdqs-frontend` is not sending a `Host`
header when proxying to your Wikibase. Apache on the upstream returns 421
when it cannot match a VirtualHost by hostname.

**Fix:** Verify that `config/wdqs-frontend-default.conf` contains
`proxy_set_header Host $WIKIBASE_HOST;` in the `/proxy/wikibase` location
block. Check the generated nginx config inside the container:

```bash
docker exec wikibase-data-services-wdqs-frontend-1 cat /etc/nginx/conf.d/default.conf
```

---

### WDQS frontend shows no data / wrong prefixes

Queries return no results even after a successful data load, or entity
URIs use the wrong prefix.

**Cause:** The `wdqs-frontend` image `:2` uses different volume mount
paths than `:1`. Mounting config files to the wrong paths causes silent
misconfiguration — the container starts normally but uses default values.

**Fix:** Verify the volume mounts in `docker-compose.yml` use the correct
paths for image `:2`:

| File | Correct mount destination |
|---|---|
| `wdqs-frontend-custom-config.json` | `/templates/wdqs-frontend-config.json.template` |
| `wdqs-frontend-default.conf` | `/templates/nginx-default.conf.template` |

---

### QuickStatements batch mode stuck at 0%

Interactive ("Run") imports work but batch ("Run in background") imports
never progress.

**Cause:** The upstream `wikibase/quickstatements:1` image is missing the
`mysqli` PHP extension and has no batch runner process. This stack fixes
both via `Dockerfile.quickstatements`.

**Fix:** Ensure the container is built from the local Dockerfile, not
pulled from the upstream image:

```bash
docker compose build quickstatements
docker compose up -d quickstatements
```

See [docs/decisions/006-quickstatements-batch-fix.md](docs/decisions/006-quickstatements-batch-fix.md)
for the full explanation.

---

## Architecture decisions

Key design decisions are documented in [docs/decisions/](docs/decisions/):

| ADR | Decision |
|---|---|
| [001](docs/decisions/001-no-wikibase-in-docker.md) | Wikibase and MariaDB run on the host, not in Docker |
| [002](docs/decisions/002-traefik-internal-only.md) | Traefik handles internal routing only; TLS terminated externally |
| [004](docs/decisions/004-wdqs-proxy-removal.md) | wdqs-proxy removed; wdqs-frontend connects directly to Blazegraph |
| [005](docs/decisions/005-concept-uri-assembly.md) | WIKIBASE_CONCEPT_URI assembled in docker-compose.yml, not in .env |
| [006](docs/decisions/006-quickstatements-batch-fix.md) | QuickStatements batch processing fix for self-hosted deployment |

---

## Real-world usage

This stack is the primary deployment for
[WikiTrek](https://wikitrek.org) — an Italian Star Trek wiki running
MediaWiki 1.43 with Wikibase and Semantic MediaWiki.

---

## Images

All images are from the official
[Wikibase Suite](https://hub.docker.com/u/wikibase) by Wikimedia Germany.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to report issues, open
pull requests, and format commit messages.

---

## License

[GNU General Public License v2.0](LICENSE.md)