# QuickStatements database setup guide

QuickStatements uses two MariaDB databases on the host to track batch jobs
and OAuth sessions. These databases must be created and initialised before
starting the QuickStatements container for the first time.

This is a one-time setup step performed by a system administrator on the
host running MariaDB.

---

## Prerequisites

- MariaDB is installed and running on the host
- You have root or equivalent access to MariaDB
- You have chosen values for `QS_DB_USER` and `QS_DB_PASSWORD` in `.env`

---

## Step 1 — Configure MariaDB to listen on the Docker bridge gateway

QuickStatements runs inside a Docker container. To reach the host MariaDB,
the container connects via the Docker bridge gateway (`172.18.0.1`). MariaDB
must be configured to accept connections on that address in addition to
`127.0.0.1`.

Add or update the `bind-address` line in your MariaDB configuration
(typically `/etc/mysql/mariadb.conf.d/50-server.cnf`):

```ini
[mysqld]
bind-address        = 127.0.0.1,172.18.0.1
skip-name-resolve
```

`skip-name-resolve` prevents DNS-based authentication mismatches when the
connecting IP resolves to an unexpected hostname.

Restart MariaDB to apply the change:

```bash
sudo systemctl restart mariadb
```

---

## Step 2 — Allow the Docker network through the firewall

If UFW is active on the host, add a rule to allow the Docker bridge subnet
to reach MariaDB on port 3306.

Add the following to `/etc/ufw/before.rules`, **before** the `COMMIT` line
in the `filter` table section:

```
-A ufw-before-input -s 172.18.0.0/16 -p tcp --dport 3306 -j ACCEPT
```

Then reload UFW:

```bash
sudo ufw reload
```

> **Why the subnet, not the interface name?**
> Using `172.18.0.0/16` instead of the Docker bridge interface name (e.g.
> `br-xxxx`) ensures the rule survives interface renames when the stack is
> recreated. Docker may assign a new interface name on each `docker compose
> down` / `up` cycle, but the subnet stays fixed because it is pinned in
> `docker-compose.yml`.

---

## Step 3 — Create the databases and user

Log in to MariaDB as root:

```bash
sudo mariadb
```

Run the following SQL, replacing `your_strong_password_here` with the value
you set for `QS_DB_PASSWORD` in `.env`:

```sql
-- Batch job tracking database
CREATE DATABASE `qsbot__quickstatements_p`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- OAuth session database
-- ToolforgeCommon derives this name automatically from the first database
-- by replacing '_p' with '_auth' — the name must match exactly.
CREATE DATABASE `qsbot__quickstatements_auth`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- User for container connections (from the Docker bridge subnet)
CREATE USER 'qsbot'@'172.18.0.%' IDENTIFIED BY 'your_strong_password_here';

-- User for local connections (useful for manual inspection and maintenance)
CREATE USER 'qsbot'@'localhost' IDENTIFIED BY 'your_strong_password_here';

-- Grant full access to both databases
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_p`.*    TO 'qsbot'@'172.18.0.%';
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_auth`.* TO 'qsbot'@'172.18.0.%';
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_p`.*    TO 'qsbot'@'localhost';
GRANT ALL PRIVILEGES ON `qsbot__quickstatements_auth`.* TO 'qsbot'@'localhost';

FLUSH PRIVILEGES;
```

> **Database names:** `qsbot__quickstatements_p` and
> `qsbot__quickstatements_auth` are the names expected by `ToolforgeCommon`
> based on the `QS_DB_USER` value (`qsbot`). If you use a different
> `QS_DB_USER`, adjust the database names accordingly:
> `<user>__quickstatements_p` and `<user>__quickstatements_auth`.

---

## Step 4 — Apply the corrected schema

The upstream QuickStatements `schema.sql` contains two incompatibilities
with MariaDB 11+:

1. **Prefix index on an `int` column** (`KEY user (user(191))`) — rejected
   by MariaDB 11. The prefix length must be removed.
2. **Empty string default on an `int` column** (`DEFAULT ''`) — rejected in
   strict SQL mode. Must be `DEFAULT 0`.

Apply the corrected schema to both databases. Still in the MariaDB shell:

```sql
-- Apply schema to the batch job tracking database
USE `qsbot__quickstatements_p`;

CREATE TABLE IF NOT EXISTS `batch` (
  `id`         int(11)      NOT NULL AUTO_INCREMENT,
  `user`       int(11)      NOT NULL DEFAULT 0,
  `name`       varchar(255) NOT NULL DEFAULT '',
  `status`     varchar(16)  NOT NULL DEFAULT 'INIT',
  `message`    text,
  `ts_created` timestamp    NOT NULL DEFAULT current_timestamp(),
  `ts_last`    timestamp    NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `user` (`user`)       -- no prefix length: int columns do not support it
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `batch_command` (
  `batch_id`   int(11)      NOT NULL,
  `num`        int(11)      NOT NULL,
  `json`       mediumtext   NOT NULL,
  `status`     varchar(16)  NOT NULL DEFAULT 'INIT',
  `message`    text,
  `ts_last`    timestamp    NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`batch_id`, `num`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Apply the same schema to the OAuth session database
USE `qsbot__quickstatements_auth`;

CREATE TABLE IF NOT EXISTS `batch` (
  `id`         int(11)      NOT NULL AUTO_INCREMENT,
  `user`       int(11)      NOT NULL DEFAULT 0,
  `name`       varchar(255) NOT NULL DEFAULT '',
  `status`     varchar(16)  NOT NULL DEFAULT 'INIT',
  `message`    text,
  `ts_created` timestamp    NOT NULL DEFAULT current_timestamp(),
  `ts_last`    timestamp    NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `user` (`user`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `batch_command` (
  `batch_id`   int(11)      NOT NULL,
  `num`        int(11)      NOT NULL,
  `json`       mediumtext   NOT NULL,
  `status`     varchar(16)  NOT NULL DEFAULT 'INIT',
  `message`    text,
  `ts_last`    timestamp    NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`batch_id`, `num`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

EXIT;
```

---

## Step 5 — Verify connectivity from the container

After starting the QuickStatements container, verify it can reach the host
MariaDB:

```bash
docker exec -it wikibase-data-services-quickstatements-1 \
  bash -c 'php -r "
    \$conn = new mysqli(\"tools.db.svc.wikimedia.cloud\", \"qsbot\", getenv(\"QS_DB_PASSWORD\"), \"qsbot__quickstatements_p\");
    if (\$conn->connect_error) { echo \"FAIL: \" . \$conn->connect_error . \"\n\"; } else { echo \"OK\n\"; }
  "'
```

A response of `OK` confirms the container can connect. If it returns `FAIL`,
check:

- MariaDB is listening on `172.18.0.1`: `ss -tlnp | grep 3306`
- The UFW rule is in place: `sudo ufw status verbose`
- The user and password match `.env`: `sudo mariadb -u qsbot -p -h 172.18.0.1`

---

## Ongoing maintenance

### Inspecting batch status

```bash
sudo mariadb qsbot__quickstatements_p \
  -e "SELECT id, user, name, status, ts_created FROM batch ORDER BY id DESC LIMIT 10;"
```

Batch status values:

| Status | Meaning |
|---|---|
| `INIT` | Created, not yet picked up by the runner |
| `RUN` | Currently being processed |
| `DONE` | Completed successfully |
| `ERROR` | Failed — check the `message` column for details |

### Checking the batch runner log

```bash
docker exec wikibase-data-services-quickstatements-1 \
  tail -50 /var/log/quickstatements/bot.log
```

### Clearing stuck batches

If a batch is stuck in `RUN` status after a container restart (the runner
was interrupted mid-batch), reset it manually:

```bash
sudo mariadb qsbot__quickstatements_p \
  -e "UPDATE batch SET status='INIT' WHERE status='RUN';"
```

The cron runner will pick it up within the next minute.