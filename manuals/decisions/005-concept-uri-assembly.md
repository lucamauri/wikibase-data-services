# ADR 005 — WIKIBASE_CONCEPT_URI assembled in docker-compose.yml, not in .env

**Status:** Accepted  
**Date:** May 2026

## Context

`WIKIBASE_CONCEPT_URI` is an environment variable consumed by the
`wdqs-updater` container. It tells the Blazegraph Munger what URI prefix
to expect for Wikibase entities in the RDF stream — for example:

```
https://data.example.org/
```

The Munger uses this value to validate the subject URI of every incoming
RDF triple. If the subject does not start with the concept URI, the Munger
rejects it with a `BadSubjectException` and the triple is not written to
Blazegraph.

The natural instinct is to set this variable in `.env` alongside other
Wikibase connection variables. Several sources (older tutorials, forks of
this stack) do exactly that — and typically set it with a `/entity/` suffix:

```env
WIKIBASE_CONCEPT_URI=https://data.example.org/entity/
```

This is incorrect for a self-hosted Wikibase and causes the updater to
silently fail on every entity update.

## Decision

`WIKIBASE_CONCEPT_URI` is **not** set in `.env`. It is assembled in
`docker-compose.yml` from existing variables:

```yaml
WIKIBASE_CONCEPT_URI: ${WIKIBASE_SCHEME}://${WIKIBASE_HOST}/
```

The `template.env` file includes a prominent comment explaining this and
warning against adding the variable manually.

## Reasoning

### The /entity/ suffix trap

On Wikidata, entity URIs look like:

```
https://www.wikidata.org/entity/Q42
```

This leads people to believe `WIKIBASE_CONCEPT_URI` should include
`/entity/`. However, on a self-hosted Wikibase the concept URI is simply
the base URL of the instance with a trailing slash:

```
https://data.example.org/
```

The `/entity/` part is appended by Wikibase itself when generating entity
URIs — it is not part of the concept URI prefix.

### What happens with the wrong value

If `WIKIBASE_CONCEPT_URI` is set to `https://data.example.org/entity/`,
the Munger receives RDF triples whose subject URIs look like:

```
https://data.example.org/entity/Q1
```

It then checks whether this subject starts with the concept URI
`https://data.example.org/entity/`. So far so good — but internally
the Munger also reconstructs the full entity URI by appending the entity
ID to the concept URI, producing:

```
https://data.example.org/entity/entity/Q1
```

This doubled `/entity/entity/` path does not match any real entity, and
the Munger throws `BadSubjectException`. The updater logs fill with errors
and no data reaches Blazegraph.

### Why assembly in docker-compose.yml prevents the mistake

By assembling the value from `${WIKIBASE_SCHEME}://${WIKIBASE_HOST}/` in
`docker-compose.yml`, the correct format is enforced automatically. An
operator who sets `WIKIBASE_SCHEME=https` and `WIKIBASE_HOST=data.example.org`
gets the right value without ever thinking about the trailing slash or the
absence of `/entity/`.

If the variable were in `.env`, every operator would need to know the
correct format — and the failure mode (silent data loss, cryptic Java
exception in logs) is severe enough to justify removing the opportunity
for error entirely.

## Consequences

- `WIKIBASE_CONCEPT_URI` must never be added to `.env` — doing so would
  cause the value to be set twice, with `.env` taking precedence and likely
  carrying the wrong format
- `template.env` includes a comment explaining the absence of this variable
  and warning against adding it
- Operators migrating from other stacks that set this variable in `.env`
  must remove it before deploying this stack