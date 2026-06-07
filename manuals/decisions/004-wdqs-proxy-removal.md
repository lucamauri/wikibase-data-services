# ADR 004 — wdqs-proxy removed; wdqs-frontend connects directly to Blazegraph

**Status:** Accepted — supersedes ADR 003  
**Date:** May 2026

## Context

ADR 003 documented the decision to keep `wdqs-proxy` between `wdqs-frontend`
and Blazegraph. The proxy enforced three constraints:

1. Only SPARQL, LDF, and asset paths were reachable (Blazegraph admin hidden)
2. All requests carried `X-BIGDATA-READ-ONLY: yes` (write queries rejected)
3. `X-BIGDATA-MAX-QUERY-MILLIS: 60000` (runaway queries killed after 60s)

The upstream Wikibase Suite Deploy (`wmde/wikibase-release-pipeline`) does not
include `wdqs-proxy` in its production `deploy/` configuration. It was
present in the upstream test environment but removed from deploy on the basis
that Blazegraph is already unreachable from outside the Docker network.

## Decision

Remove `wdqs-proxy` from this stack. `wdqs-frontend` now connects directly
to `wdqs` on port 9999 (Blazegraph's native port).

This aligns the stack with the upstream deploy configuration.

## Reasoning

### The proxy's protections are already provided elsewhere

**Network isolation:** Blazegraph's port 9999 is on the Docker internal
network only. It is not exposed to the host and has no Traefik label —
there is no path from the internet to Blazegraph regardless of what sits
in front of it. A misconfiguration in Apache or Traefik cannot expose
Blazegraph's admin interface because the interface is not reachable at
the network level.

**Outer security layer:** Apache + Anubis sit in front of all public
traffic. Anubis provides bot filtering and rate limiting before a request
ever reaches Traefik or any container. This is a more capable outer layer
than the proxy provided.

**Read-only enforcement:** The `wdqs-frontend` nginx configuration
(`config/wdqs-frontend-default.conf`) proxies SPARQL queries directly to
Blazegraph's `/bigdata/namespace/wdq/sparql` endpoint. Only this path
and `/proxy/wikibase` are exposed through the frontend — Blazegraph's
write endpoints and admin UI are not reachable through nginx.

**Query timeouts:** Blazegraph has a configurable default query timeout
that can be set at the namespace level. For most self-hosted wikis with
moderate query load, the absence of the proxy-enforced 60-second timeout
is acceptable. Operators who need hard query limits can configure
Blazegraph's namespace timeout directly.

### Cost of keeping the proxy

- One additional container with its own image pull, memory footprint,
  and potential version drift from upstream
- An extra network hop on every SPARQL request
- Divergence from upstream deploy makes it harder to track upstream
  changes and apply fixes

## Consequences

- `wdqs-frontend` uses `wdqs:9999` as its upstream in the nginx config
  (`proxy_pass http://$WDQS_HOST:9999`) — not port 80 via the proxy
- Blazegraph remains unreachable from the internet via network isolation
- ADR 003 is superseded and kept for historical reference
- If the upstream team ships a Traefik-based query timeout mechanism in
  a future version, this decision should be revisited

## Note on ADR 003

ADR 003 argued for keeping `wdqs-proxy` as a defence-in-depth layer.
That reasoning was valid at the time. The decision to remove it is based
on the subsequent confirmation that network isolation alone is sufficient
given how this stack is deployed, and on the value of staying aligned
with upstream.