# QuickStatements OAuth setup guide

QuickStatements authenticates users via OAuth 1.0a against your Wikibase
instance. Before users can log in, you must register an OAuth consumer on
your wiki and copy the resulting credentials into `.env`.

This is a one-time setup step performed by a wiki administrator.

---

## Prerequisites

- You must be logged in to your Wikibase as an administrator
- The MediaWiki **OAuth** extension must be installed and enabled
  (`wfLoadExtension('OAuth');` in `LocalSettings.php`)
- QuickStatements must already be running and reachable at its public URL
  (so the callback URL is valid when you register)

---

## Step 1 — Open the OAuth consumer registration form

In your Wikibase, navigate to:

```
Special:OAuthConsumerRegistration
```

Or follow the link: `https://data.example.org/wiki/Special:OAuthConsumerRegistration`
(replace `data.example.org` with your `WIKIBASE_HOST`).

Click **"Request a token for a new consumer"**.

---

## Step 2 — Fill in the registration form

| Field | Value to enter |
|---|---|
| **Application name** | `QuickStatements` (or any name you recognise) |
| **Application description** | `Batch editing tool for Wikibase` |
| **OAuth protocol version** | `OAuth 1.0a` |
| **Callback URL** | `https://qs.example.org/api.php` — replace with your `QUICKSTATEMENTS_PUBLIC_HOST` |
| **Contact email** | Your admin email address |
| **Applicable project** | Select your wiki (or leave as default if only one wiki) |
| **Rights** | Check **Edit existing pages** and **Create, edit, and move pages** |

> **Callback URL format:** the callback URL must be exactly:
> ```
> https://<QUICKSTATEMENTS_PUBLIC_HOST>/api.php
> ```
> Do not add a trailing slash. Do not use the bare hostname without `/api.php`.

Leave all other fields at their defaults and submit the form.

---

## Step 3 — Copy the consumer key and secret

After submitting, MediaWiki will display two values:

- **Consumer key** — a long alphanumeric string
- **Consumer secret** — a long alphanumeric string

**Copy both immediately.** The secret is only shown once. If you lose it
you will need to register a new consumer.

Open your `.env` file and fill in the three OAuth variables:

```env
# The key shown after registration
OAUTH_CONSUMER_KEY=paste_your_consumer_key_here

# The secret shown after registration (shown once — save it now)
OAUTH_CONSUMER_SECRET=paste_your_consumer_secret_here

# Base URL of your wiki root — no trailing slash
# The stack appends /index.php?title=Special:OAuth internally
OAUTH_SCRIPT_PATH=https://data.example.org/w
```

> **`OAUTH_SCRIPT_PATH`** is the base path of your MediaWiki installation,
> not the full OAuth URL. For a standard MediaWiki install at
> `https://data.example.org/w/`, set it to `https://data.example.org/w`.
> For a custom path (e.g. `/dt/`), set it to `https://data.example.org/dt`.

---

## Step 4 — Approve the consumer as a wiki admin

The newly registered consumer starts in **pending** state. It must be
approved before QuickStatements can use it.

Navigate to:

```
Special:OAuthManageConsumers/proposed
```

Find your QuickStatements consumer in the list and click **"Review/manage"**.
Click **"Approve"** and confirm.

> If you registered the consumer while logged in as an admin, you may be
> able to approve it immediately on the same page after submission.
> Look for an "Approve" button before navigating away.

---

## Step 5 — Restart the QuickStatements container

After updating `.env` with the new credentials, restart the container so
it picks up the new values:

```bash
docker compose up -d quickstatements
```

---

## Step 6 — Test the login

Open QuickStatements in your browser at your `QUICKSTATEMENTS_PUBLIC_HOST`.
Click **"Log in"**. You should be redirected to your Wikibase OAuth
authorisation page. Approve the request and you will be redirected back
to QuickStatements, now logged in.

If the login fails, check:

- The callback URL in `Special:OAuthManageConsumers` matches exactly
  `https://<QUICKSTATEMENTS_PUBLIC_HOST>/api.php`
- The consumer status is **approved**, not pending or rejected
- `OAUTH_SCRIPT_PATH` in `.env` does not have a trailing slash
- The QuickStatements container was restarted after editing `.env`
- The QuickStatements container logs for OAuth errors:
  ```bash
  docker logs wikibase-data-services-quickstatements-1 --tail 50
  ```

---

## Revoking access

To revoke a user's QuickStatements access, navigate to
`Special:OAuthManageConsumers` on your wiki and disable or delete the
consumer. All existing sessions will be invalidated immediately.