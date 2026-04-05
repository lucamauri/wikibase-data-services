# ADR 001 — Wikibase and MariaDB run on the host, not in Docker

**Status:** Accepted  
**Date:** April 2026

## Context

The upstream Wikibase Suite Deploy includes Wikibase, MediaWiki, and MariaDB
as Docker containers alongside the auxiliary services. Many self-hosters,
however, already run Wikibase on a native LAMP stack, either because they
set it up before Docker-based options were mature, or because they want
direct control over PHP version, Apache configuration, and database tuning.

## Decision

This stack explicitly excludes Wikibase, MediaWiki, MariaDB, and any job
runner containers. It provides only the auxiliary services that have no
LAMP equivalent: Blazegraph, Elasticsearch, QuickStatements, and their
supporting pieces.

## Consequences

- Users must have a working Wikibase installation on the host before
  deploying this stack
- The WDQS updater reaches Wikibase via its public hostname over HTTPS,
  exactly as an external client would — no special internal networking needed
- The stack is significantly lighter (~3 GB RAM) than a full Wikibase Suite
  deployment (~5–6 GB RAM)
- Updates to MediaWiki, Wikibase, and MariaDB are managed independently of
  this stack, which is appropriate when the host LAMP stack has its own
  maintenance and upgrade cycle
