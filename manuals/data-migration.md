# Data Migration Guide

This document explains how to migrate Blazegraph (WDQS) and Elasticsearch
data from an existing server to a new one running this stack.

---

## Blazegraph (WDQS) migration

Blazegraph stores all SPARQL-queryable entity data. Migrating it avoids
a full re-sync from scratch, which can take hours or days on a large wiki.

### Option A — Full dump and reload (recommended for clean migration)

This is the safest approach. It produces a fresh RDF dump from your
Wikibase instance and loads it into Blazegraph on the new server.

**Step 1 — Generate an RDF dump on the host running Wikibase:**

```bash
# Run from your Wikibase maintenance directory
# e.g. /var/www/mw/dt/extensions/Wikibase/repo/maintenance
php dumpRdf.php --format=ttl > /tmp/wikidump.ttl
gzip /tmp/wikidump.ttl
```

**Step 2 — Copy the dump to the new server:**

```bash
scp /tmp/wikidump.ttl.gz lmauri@<new-server-ip>:/tmp/
```

**Step 3 — Start only the wdqs container on the new server:**

```bash
docker compose up -d wdqs
```

**Step 4 — Copy the dump into the container:**

```bash
docker cp /tmp/wikidump.ttl.gz datatrek-services-wdqs-1:/wdqs/data/wikidump-000000001.ttl.gz
```

The filename must follow the pattern `wikidump-NNNNNNNNN.ttl.gz`.
For large dumps (>500k items) you may need to run the munge script first
to split it — see the Wikibase documentation for `mungeForImport.sh`.

**Step 5 — Load the data:**

```bash
docker exec -it datatrek-services-wdqs-1 bash
./loadData.sh -n wdq -d /wdqs/data/
exit
```

**Step 6 — Start the rest of the stack:**

```bash
docker compose up -d
```

---

### Option B — Volume copy (faster, carries over existing state)

Copy the Docker volume contents directly. Use this when the source server
also runs this stack (or a compatible setup).

**On the source server — export the volume:**

```bash
docker run --rm \
  -v dss-deploy_wdqs-data:/source:ro \
  -v /tmp:/backup \
  alpine tar czf /backup/wdqs-data.tar.gz -C /source .
```

**Copy to the new server:**

```bash
scp /tmp/wdqs-data.tar.gz lmauri@<new-server-ip>:/tmp/
```

**On the new server — create the volume and import:**

```bash
# Create the volume (compose must have been run at least once, or create manually)
docker volume create datatrek-services_wdqs-data

docker run --rm \
  -v datatrek-services_wdqs-data:/target \
  -v /tmp:/backup \
  alpine tar xzf /backup/wdqs-data.tar.gz -C /target
```

Then start the stack normally.

---

## Elasticsearch migration

Elasticsearch data is regenerable — losing it means running the CirrusSearch
setup scripts again, which is slower but not destructive.

### Option A — Re-index from scratch (simplest)

After starting the stack on the new server:

```bash
# Run from your MediaWiki directory on the host
php maintenance/run.php updateSearchIndexConfig
php maintenance/run.php forceSearchIndex
```

This is the recommended approach unless your wiki is very large (millions
of pages), in which case re-indexing may take a long time.

### Option B — Volume copy

Same procedure as Blazegraph Option B above, substituting
`dss-deploy_elasticsearch-data` and `datatrek-services_elasticsearch-data`
as the volume names.

> ⚠️ Elasticsearch volume copies can fail if the Elasticsearch version
> differs between source and destination. If the copy fails to start,
> fall back to Option A.

---

## QuickStatements OAuth tokens

The `quickstatements-data` volume holds OAuth tokens. If you copy it to
the new server, existing authenticated sessions will continue to work.

If you do not copy it, users will simply need to re-authenticate with
their Wikibase credentials — no data is lost.

Volume copy procedure is identical to Blazegraph Option B.
