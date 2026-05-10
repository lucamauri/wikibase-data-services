# Data loading guide

This document explains how to perform an initial load of your Wikibase entity
data into Blazegraph (WDQS) after first deploying the stack.

The WDQS updater keeps Blazegraph in sync with ongoing edits automatically.
But on first deployment, Blazegraph starts empty — the updater only processes
changes that happen *after* it starts, and will not back-fill historical data.
A full RDF dump load is required to populate Blazegraph with your existing data.

> If you are migrating data from an existing server rather than loading from
> scratch, see [docs/data-migration.md](data-migration.md) instead.

---

## Overview

```
Wikibase host          Docker host            Blazegraph container
─────────────          ───────────            ────────────────────
dumpRdf.php ──gzip──►  wikidump-000000001     loadData.sh
                       .ttl.gz ──docker cp──► /wdqs/data/
```

The dump is generated on the host running Wikibase, copied to the Docker host
(if different), then loaded into the Blazegraph container directly.

---

## Step 1 — Start only the wdqs container

The load process writes directly to the Blazegraph data volume. Start only
`wdqs` so the volume exists and Blazegraph is available, but the updater is
not yet running (it would start polling before the data is ready).

```bash
docker compose up -d wdqs
```

Wait for it to become healthy:

```bash
docker compose ps wdqs
# Status should show: healthy
```

---

## Step 2 — Generate an RDF dump on your Wikibase host

Run the Wikibase RDF dump maintenance script on the host where MediaWiki and
Wikibase are installed. Replace the path with the actual location of your
Wikibase extension:

```bash
php /var/www/html/extensions/Wikibase/repo/maintenance/dumpRdf.php \
  --format=ttl \
  | gzip > ~/wikidump-000000001.ttl.gz
```

**File naming is important.** The `loadData.sh` script expects files named:

```
wikidump-XXXXXXXXX.ttl.gz
```

Where `XXXXXXXXX` is a nine-digit zero-padded sequential number starting
at `000000001`. If you have multiple dump files (see the large wiki note
below), name them `wikidump-000000001.ttl.gz`, `wikidump-000000002.ttl.gz`,
and so on.

The dump may take several minutes on a large wiki. For reference, a wiki
with ~13,000 items and ~200 properties produces a dump of roughly 10–20 MB
compressed.

---

## Step 3 — Copy the dump to the Docker host

If your Wikibase and Docker stack run on the same host, skip this step.

If they run on separate hosts, copy the dump file over:

```bash
scp ~/wikidump-000000001.ttl.gz user@your-docker-host:~/
```

---

## Step 4 — Copy the dump into the Blazegraph container

```bash
docker cp ~/wikidump-000000001.ttl.gz \
  wikibase-data-services-wdqs-1:/wdqs/data/wikidump-000000001.ttl.gz
```

The container name `wikibase-data-services-wdqs-1` is the default when the
compose project is named `wikibase-data-services` (set at the top of
`docker-compose.yml`). Verify with `docker ps` if unsure.

---

## Step 5 — Load the data

Open a shell inside the Blazegraph container and run the load script:

```bash
docker exec -it wikibase-data-services-wdqs-1 bash
./loadData.sh -n wdq -d /wdqs/data/
exit
```

The `-n wdq` flag specifies the Blazegraph namespace. The `-d` flag points
to the directory containing your dump file(s).

You will see output like:

```
Loading file: /wdqs/data/wikidump-000000001.ttl.gz
...
File not found, terminating
```

**"File not found, terminating" is normal and expected.** The script
iterates through sequentially numbered dump files until it finds one that
does not exist, then stops. This is not an error — it means all available
dump files have been loaded.

The load may take several minutes depending on the size of your wiki.

---

## Step 6 — Start the rest of the stack

Once the load is complete, start the remaining services including the updater:

```bash
docker compose up -d
```

The updater will begin polling Wikibase for changes and keeping Blazegraph
in sync from this point forward.

---

## Verifying the load

Check the triple count via SPARQL to confirm data was loaded:

```bash
curl -s "http://127.0.0.1:8880/sparql" \
  -H "Host: query.your-wiki.org" \
  --data-urlencode "query=SELECT (COUNT(*) AS ?count) WHERE { ?s ?p ?o }" \
  -H "Accept: application/sparql-results+json"
```

Replace `query.your-wiki.org` with your `WDQS_FRONTEND_PUBLIC_HOST` value
and `8880` with your `TRAEFIK_HOST_PORT` if you changed it.

A successful response will contain a `count` value matching the number of
RDF triples in your Wikibase. A small wiki with a few thousand items
typically has several hundred thousand triples.

---

## Note on large wikis

For wikis with very large numbers of items (hundreds of thousands or more),
the RDF dump may need to be split before loading. Use the Wikibase
`mungeForImport.sh` script to split the dump into chunks:

```bash
# Inside the wdqs container
./mungeForImport.sh -d /wdqs/data/ -f /wdqs/data/wikidump-000000001.ttl.gz
```

This produces multiple sequentially numbered files that `loadData.sh` will
load in order. Refer to the
[Wikibase documentation](https://www.mediawiki.org/wiki/Wikibase/WDQS#Loading_data)
for details on sizing and splitting large dumps.