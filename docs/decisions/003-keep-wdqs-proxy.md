# ADR 003 — wdqs-proxy is kept despite being absent from upstream deploy

**Status:** Accepted  
**Date:** April 2026

## Context

The upstream Wikibase Suite Deploy (`deploy/docker-compose.yml`) does not
include the `wdqs-proxy` container. The proxy is present in the upstream
test environment and as a published image (`wikibase/wdqs-proxy`), but the
upstream team is considering removing it from deploy in favour of routing
SPARQL through the central Traefik proxy (PRs #767 and #833).

In the upstream deploy setup, Traefik only exposes the `wdqs-frontend`
service publicly — Blazegraph's port 9999 is unreachable from outside the
Docker network regardless. This makes `wdqs-proxy` redundant there.

## Decision

This stack keeps `wdqs-proxy` between the frontend and Blazegraph.

## Reasoning

In this stack, the path from the internet to Blazegraph is:

```
Apache → Traefik → wdqs-frontend → wdqs-proxy → wdqs (Blazegraph :9999)
```

`wdqs-proxy` enforces three constraints regardless of what sits in front:

1. Only `/bigdata/namespace/.../sparql`, `/ldf`, and `/assets` are reachable
2. All requests carry `X-BIGDATA-READ-ONLY: yes` — write queries are rejected
3. `X-BIGDATA-MAX-QUERY-MILLIS: 60000` — runaway queries are killed after 60s

Without `wdqs-proxy`, a misconfiguration in Apache or Traefik could expose
Blazegraph's full admin interface, including write endpoints. The proxy
provides a defence-in-depth layer that costs 4 MB RAM.

## Consequences

- The stack includes one more container than the upstream deploy
- `wdqs-frontend` connects to `wdqs-proxy`, not directly to `wdqs`
- If the upstream team ships a Traefik-based replacement for these
  constraints in a future version, this decision should be revisited
