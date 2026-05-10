# Elasticsearch setup guide

This document explains how to connect your MediaWiki/Wikibase installation
to the containerised Elasticsearch provided by this stack, and how to
build and maintain the search index.

Elasticsearch powers the **CirrusSearch** MediaWiki extension, which
replaces MediaWiki's built-in search with full-text search across all
pages and Wikibase entities.

---

## Prerequisites

- The stack is running and the `elasticsearch` container is healthy:
  ```bash
  docker compose ps elasticsearch
  # Status should show: healthy
  ```
- The following MediaWiki extensions are installed on your Wikibase host:
  - **CirrusSearch** (`wfLoadExtension('CirrusSearch');`)
  - **Elastica** (`wfLoadExtension('Elastica');`)

If you do not have these extensions, install them before proceeding.
Both are available via the standard MediaWiki extension distribution.

---

## Step 1 — Verify Elasticsearch is reachable from the host

The `elasticsearch` container exposes its HTTP API on `127.0.0.1` at the
port defined by `ELASTICSEARCH_HOST_PORT` in `.env` (default: `9200`).

Test connectivity from your Wikibase host:

```bash
curl -s http://127.0.0.1:9200
```

A healthy response looks like:

```json
{
  "name" : "...",
  "cluster_name" : "docker-cluster",
  "version" : { ... },
  "tagline" : "You Know, for Search"
}
```

If this fails, check:
- The `elasticsearch` container is running: `docker compose ps`
- `ELASTICSEARCH_HOST_PORT` in `.env` matches the port you are testing
- No firewall rule is blocking `127.0.0.1:9200` on the host

---

## Step 2 — Configure MediaWiki to use Elasticsearch

Add the following to your `LocalSettings.php` on the Wikibase host.
Place it **after** the `wfLoadExtension` calls for CirrusSearch and Elastica:

```php
// Use CirrusSearch as the search backend
$wgSearchType = 'CirrusSearch';

// Address of the Elasticsearch container
// Bound to 127.0.0.1 — only reachable from the host machine
$wgCirrusSearchServers = [ '127.0.0.1' ];

// Only needed if ELASTICSEARCH_HOST_PORT in .env differs from 9200
// $wgCirrusSearchPort = 9200;
```

> **Note:** If your Wikibase and Docker stack run on separate hosts,
> Elasticsearch will not be reachable at `127.0.0.1`. You will need to
> either expose the port on a private network interface, or set up a
> secure tunnel (e.g. SSH port forwarding) between the two hosts.
> Exposing Elasticsearch on a public interface is not recommended.

---

## Step 3 — Run the CirrusSearch setup scripts

These scripts create the Elasticsearch index structure required by
CirrusSearch. Run them from your MediaWiki installation directory on
the Wikibase host:

```bash
# Create or update the index configuration
php maintenance/run.php updateSearchIndexConfig

# Index all existing pages and entities
php maintenance/run.php forceSearchIndex
```

`forceSearchIndex` may take several minutes on a large wiki. It indexes
every page, so the time depends on the number of pages and entities in
your Wikibase.

> **Older MediaWiki versions:** if `maintenance/run.php` is not available
> (MediaWiki < 1.40), use the legacy syntax instead:
> ```bash
> php maintenance/updateSearchIndexConfig.php
> php maintenance/forceSearchIndex.php
> ```

---

## Step 4 — Verify search is working

Open your wiki in a browser and try a search. Results should appear
immediately for existing page titles.

For a more direct check, query the Elasticsearch index from the command line:

```bash
curl -s "http://127.0.0.1:9200/_cat/indices?v"
```

This lists all indices. You should see one or more indices named after
your wiki's database name (e.g. `my_wiki_content`, `my_wiki_general`).

---

## Re-indexing

Re-indexing is needed when:
- You upgrade CirrusSearch to a new version
- You change the index configuration
- The Elasticsearch data volume is lost or reset
- Search results are stale or missing pages

To re-index from scratch:

```bash
php maintenance/run.php updateSearchIndexConfig
php maintenance/run.php forceSearchIndex
```

These are the same commands as the initial setup. They are safe to re-run
at any time — `forceSearchIndex` rebuilds the index without downtime.

---

## Monitoring and maintenance

### Check index health

```bash
curl -s http://127.0.0.1:9200/_cluster/health?pretty
```

A healthy cluster shows `"status": "green"` or `"status": "yellow"`.
Yellow is normal for a single-node deployment (some replica shards cannot
be assigned when there is only one node).

### Check index size and document count

```bash
curl -s "http://127.0.0.1:9200/_cat/indices?v&h=index,docs.count,store.size"
```

### Container memory

Elasticsearch is configured with a 512 MB JVM heap by default
(`ES_JAVA_OPTS: -Xms512m -Xmx512m` in `docker-compose.yml`). This is
suitable for most self-hosted wikis. If Elasticsearch is killed by the
OOM killer, increase the heap — but keep it at or below 50% of the
host's available RAM:

```env
# In .env — no direct variable; edit docker-compose.yml ES_JAVA_OPTS directly
```

Edit the `ES_JAVA_OPTS` line in `docker-compose.yml`:

```yaml
ES_JAVA_OPTS: -Xms1g -Xmx1g -Dlog4j2.formatMsgNoLookups=true
```

Then restart the container:

```bash
docker compose up -d elasticsearch
```

---

## Data persistence

Elasticsearch data is stored in the `elasticsearch-data` Docker volume.
Losing this volume requires re-running the setup and indexing scripts —
no Wikibase data is lost, only the search index, which is fully
regenerable from MediaWiki page content.

For volume backup and migration procedures, see
[docs/data-migration.md](data-migration.md).