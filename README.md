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
| **WDQS Proxy** | Read-only, timeout-enforcing gateway in front of Blazegraph |
| **WDQS Frontend** | Browser-based SPARQL query editor |
| **Elasticsearch** | Full-text search for MediaWiki CirrusSearch |
| **QuickStatements** | Batch editing tool for Wikibase |
| **Traefik** | Internal HTTP router between containers |

> If you need a full self-hosted Wikibase stack including MediaWiki and
> MariaDB, see the official
> [Wikibase Suite Deploy](https://github.com/wmde/wikibase-release-pipeline/tree/main/deploy)
> by Wikimedia Germany.

---

## Requirements

- Docker 24.0 or later
- Docker Compose V2 (`docker compose`, not `docker-compose`)
- An existing Wikibase installation accessible via a public hostname
- A reverse proxy on the host (Apache, Nginx, Caddy…) to handle TLS and
  route traffic to Traefik — or set `TRAEFIK_BIND_ADDRESS=0.0.0.0` for
  standalone use

**RAM:** approximately 3 GB for the full stack (Blazegraph ~2 GB,
Elasticsearch ~512 MB, other services ~500 MB combined).

---

## Quick start

```bash
# 1. Clone the repository
git clone https://github.com/WikiTrek/wikibase-data-services
cd wikibase-data-services

# 2. Create your configuration
cp template.env .env
nano .env   # fill in your values — see comments in the file

# 3. Start the stack
docker compose up -d

# 4. Check that all services are healthy
docker compose ps
```

---

## Configuration

All deployment-specific values live in `.env` (gitignored, never committed).
Copy `template.env` to `.env` and fill in every variable. The template
contains a description of each variable.

The minimum required variables are:

```env
WIKIBASE_HOST=data.example.org
WIKIBASE_API_PATH=/w/api.php
WIKIBASE_CONCEPT_URI=https://data.example.org
WDQS_PUBLIC_HOST=query.example.org
QUICKSTATEMENTS_PUBLIC_HOST=qs.example.org
WIKIBASE_NAME=My Wikibase
WIKIBASE_LOGO=https://data.example.org/logo.png
WIKIBASE_FAVICON=https://data.example.org/favicon.ico
WIKIBASE_COPYRIGHT=https://data.example.org/wiki/About
WIKIBASE_EXAMPLES_PAGE_TITLE=Help:SPARQL_examples
```

---

## Reverse proxy integration

Traefik listens on `127.0.0.1:8880` by default. Your host reverse proxy
must forward requests for `WDQS_PUBLIC_HOST` and `QUICKSTATEMENTS_PUBLIC_HOST`
to that port, preserving the `Host` header.

For Apache with Anubis, see [docs/apache-integration.md](docs/apache-integration.md).

For standalone use without a host reverse proxy, set `TRAEFIK_BIND_ADDRESS=0.0.0.0`
in `.env`.

---

## Elasticsearch and MediaWiki

Add the following to your MediaWiki `LocalSettings.php`:

```php
wfLoadExtension( 'CirrusSearch' );
wfLoadExtension( 'Elastica' );
$wgSearchType = 'CirrusSearch';
$wgCirrusSearchServers = [ '127.0.0.1' ];
// Only needed if ELASTICSEARCH_HOST_PORT differs from 9200:
// $wgCirrusSearchPort = 9200;
```

Run the CirrusSearch setup scripts after first starting the stack:

```bash
php maintenance/run.php updateSearchIndexConfig
php maintenance/run.php forceSearchIndex
```

---

## Data migration

If you are migrating Blazegraph or Elasticsearch data from an existing
server, see [docs/data-migration.md](docs/data-migration.md).

---

## Architecture decisions

See [docs/decisions/](docs/decisions/) for the reasoning behind key design
choices in this project.

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

## License

MIT
