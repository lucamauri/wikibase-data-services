# Apache Integration Guide

This document explains how to configure Apache on the host to proxy public
traffic to the DataTrekServices containers via Traefik.

## Architecture

```
Internet
  │
  ▼
Apache :443 (TLS termination)
  │
  ▼
Anubis :8923 (bot protection — optional but recommended)
  │
  ▼
Apache :8080 (internal backend)
  │
  ├──► MediaWiki / Wikibase (served directly by Apache/PHP)
  │
  └──► Traefik :8880 (Docker internal router)
         │
         ├──► wdqs-frontend :80   (query.example.org)
         └──► quickstatements :80 (qs.example.org)
```

Traefik routes requests to the correct container based on the `Host` header,
which Apache preserves when proxying.

## Required Apache modules

```bash
sudo a2enmod proxy proxy_http ssl headers rewrite
sudo systemctl reload apache2
```

## VirtualHost for WDQS Frontend

Replace `query.wikitrek.org` with your `WDQS_PUBLIC_HOST` value.
Replace `8880` with your `TRAEFIK_HOST_PORT` value if you changed it.

```apache
# /etc/apache2/sites-available/query-wikitrek-le-ssl.conf

<VirtualHost *:443>
    ServerName query.wikitrek.org

    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/wikitrek.org/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/wikitrek.org/privkey.pem

    # Pass real client IP to Anubis (capital P is required — see note below)
    RequestHeader set "X-Real-IP" expr=%{REMOTE_ADDR}
    RequestHeader set "X-Forwarded-Proto" "https"
    RequestHeader set "X-Http-Version" "%{SERVER_PROTOCOL}s"

    # Proxy all traffic through Anubis for bot protection,
    # then on to the internal Apache backend at :8080
    ProxyPreserveHost On
    ProxyPass        / http://[::1]:8923/
    ProxyPassReverse / http://[::1]:8923/
</VirtualHost>

# Internal backend VirtualHost (receives traffic from Anubis)
<VirtualHost [::1]:8080>
    ServerName query.wikitrek.org

    # Forward to Traefik, which routes to the wdqs-frontend container.
    # Host header is preserved so Traefik can identify the correct service.
    ProxyPreserveHost On
    ProxyPass        / http://127.0.0.1:8880/
    ProxyPassReverse / http://127.0.0.1:8880/
</VirtualHost>
```

## VirtualHost for QuickStatements

Replace `qs.wikitrek.org` with your `QUICKSTATEMENTS_PUBLIC_HOST` value.

```apache
# /etc/apache2/sites-available/qs-wikitrek-le-ssl.conf

<VirtualHost *:443>
    ServerName qs.wikitrek.org

    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/wikitrek.org/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/wikitrek.org/privkey.pem

    RequestHeader set "X-Real-IP" expr=%{REMOTE_ADDR}
    RequestHeader set "X-Forwarded-Proto" "https"
    RequestHeader set "X-Http-Version" "%{SERVER_PROTOCOL}s"

    ProxyPreserveHost On
    ProxyPass        / http://[::1]:8923/
    ProxyPassReverse / http://[::1]:8923/
</VirtualHost>

<VirtualHost [::1]:8080>
    ServerName qs.wikitrek.org

    ProxyPreserveHost On
    ProxyPass        / http://127.0.0.1:8880/
    ProxyPassReverse / http://127.0.0.1:8880/
</VirtualHost>
```

## HTTP redirect VirtualHosts

Add a redirect for each hostname on port 80:

```apache
<VirtualHost *:80>
    ServerName query.wikitrek.org
    Redirect permanent / https://query.wikitrek.org/
</VirtualHost>

<VirtualHost *:80>
    ServerName qs.wikitrek.org
    Redirect permanent / https://qs.wikitrek.org/
</VirtualHost>
```

## Enabling the sites

```bash
sudo a2ensite query-wikitrek-le-ssl.conf qs-wikitrek-le-ssl.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

## TLS certificates

If using certbot with the Hetzner DNS plugin (wildcard cert):

```bash
sudo certbot certonly \
  --dns-hetzner \
  --dns-hetzner-credentials /etc/letsencrypt/hetzner.ini \
  -d "*.wikitrek.org" -d "wikitrek.org"
```

`query.wikitrek.org` and `qs.wikitrek.org` are covered by the existing
wildcard certificate — no additional certificate is needed.

## Critical: X-Real-IP header capitalisation

The header **must** be `X-Real-IP` (capital P). Using `X-Real-Ip` (lowercase p)
causes Anubis to fail silently with 15–30 second page loads for all users.
See the server reference document for full details.

## Anubis bot policy

Add allow rules for `query.wikitrek.org` and `qs.wikitrek.org` in
`/etc/anubis/botpolicy.yaml` if you want them protected.
QuickStatements in particular should have strict rules since it is an
editing interface — consider restricting it to logged-in users via the
Wikibase OAuth flow rather than relying on Anubis alone.
