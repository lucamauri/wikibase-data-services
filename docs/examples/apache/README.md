# Apache VirtualHost examples

This directory contains example Apache VirtualHost configuration files for
serving the wikibase-data-services stack behind Apache with TLS.

## Files

| File | Service |
|---|---|
| `query.your-wiki.org.conf` | WDQS Frontend (SPARQL query UI) |
| `qs.your-wiki.org.conf` | QuickStatements (batch editing tool) |

## Architecture

```
Internet
  │
  ▼
Apache :443  (TLS termination)
  │
  ▼
Anubis :8923  (bot filtering — optional but recommended)
  │
  ▼
Apache :8080  (internal backend, loopback only)
  │
  ▼
Traefik :8880  (Docker internal router)
  │
  ├──► wdqs-frontend    (query.your-wiki.org)
  └──► quickstatements  (qs.your-wiki.org)
```

Traefik routes requests to the correct container based on the `Host` header,
which Apache preserves via `ProxyPreserveHost On`.

## How to use

1. Copy the relevant `.conf` file to `/etc/apache2/sites-available/`
2. Replace all placeholder values (search for `your-wiki.org`)
3. Enable the site and reload Apache:

```bash
sudo a2ensite query.your-wiki.org.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

## Critical rules — read before deploying

### X-Real-IP capitalisation

The header **must** be written as `X-Real-IP` (capital P in IP).
Using `X-Real-Ip` (lowercase p) causes Anubis to fail silently —
all users experience 15–30 second page loads with no error message.

### Internal backend must use `[::1]:8080`

The `:8080` VirtualHost must bind to `[::1]:8080` (IPv6 loopback), not
`*:8080`. Binding to `*:8080` would expose the internal backend publicly,
bypassing Anubis entirely.

### `ServerName` is required on the `:8080` VirtualHost

Without `ServerName`, Apache cannot match the internal VirtualHost by
hostname. All `:8080` traffic falls through to the default host.

### `ProxyPreserveHost On` is required

Traefik identifies which container to route to using the `Host` header.
Without `ProxyPreserveHost On`, Apache replaces the `Host` header with
the proxy target address and Traefik cannot route correctly.

## TLS certificates

The example files reference a wildcard Let's Encrypt certificate obtained
via a DNS challenge. If you use certbot with a DNS plugin:

```bash
sudo certbot certonly \
  --dns-<your-plugin> \
  --dns-<your-plugin>-credentials /etc/letsencrypt/<plugin>.ini \
  -d "*.your-wiki.org" -d "your-wiki.org"
```

A wildcard certificate covers all subdomains, so both `query.your-wiki.org`
and `qs.your-wiki.org` are covered without separate certificate requests.