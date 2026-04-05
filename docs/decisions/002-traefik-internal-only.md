# ADR 002 — Traefik handles internal routing only; TLS terminated externally

**Status:** Accepted  
**Date:** April 2026

## Context

The upstream Wikibase Suite Deploy uses Traefik as the public-facing reverse
proxy, handling TLS termination via Let's Encrypt ACME and routing all
external traffic. This works well for a standalone Docker deployment with
no pre-existing web server.

For deployments where a host-level reverse proxy already exists (Apache,
Nginx, Caddy), having Traefik also bind to ports 80 and 443 creates a
conflict and duplicates concerns: two systems managing TLS certificates,
two systems handling bot protection and rate limiting.

## Decision

Traefik binds only to `127.0.0.1` on a configurable port (default 8880).
It handles HTTP routing between containers based on Docker labels, but
does not terminate TLS and does not listen on any public interface by default.

TLS termination, certificate management, and any additional security layers
(bot protection, rate limiting) are the responsibility of the host reverse
proxy.

The binding address is controlled by `TRAEFIK_BIND_ADDRESS` in `.env`,
allowing standalone deployments to set `0.0.0.0` and use Traefik as the
public-facing proxy with their own TLS configuration.

## Consequences

- In the default configuration, the host reverse proxy must forward traffic
  for the relevant hostnames to `127.0.0.1:${TRAEFIK_HOST_PORT}`
- TLS certificates are managed entirely outside this stack (e.g. via
  certbot on the host)
- Bot protection and security policies can be applied uniformly at the
  host reverse proxy level across all services (Wikibase, WDQS, QuickStatements)
- The stack is usable in standalone mode by changing one variable in `.env`
