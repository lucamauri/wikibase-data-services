# Contributing to wikibase-data-services

Thank you for your interest in contributing. This document explains how
to report issues, propose changes, and submit pull requests.

---

## Reporting issues

Use the [GitHub issue tracker](https://github.com/lucamauri/wikibase-data-services/issues)
to report bugs or request improvements.

When reporting a bug, please include:

- What you expected to happen
- What actually happened
- The output of `docker compose ps` and relevant container logs
  (e.g. `docker logs wikibase-data-services-wdqs-updater-1 --tail 50`)
- Your host OS and Docker version (`docker --version`, `docker compose version`)
- Which services are affected

Please redact any credentials or private hostnames before posting logs.

---

## Pull requests

1. **Fork** the repository and create a branch from `main`.
2. **Make your changes** — keep each PR focused on a single concern.
3. **Test your changes** locally with `docker compose up -d` and verify
   all containers reach healthy status.
4. **Update documentation** if your change affects behaviour described
   in `docs/` or `template.env`.
5. **Open a pull request** against `main` with a clear description of
   what the change does and why.

There are no automated tests beyond the GitHub Actions compose validation
(`.github/workflows/validate.yml`). Please run `docker compose config`
locally before submitting to catch syntax errors.

---

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/).

Format:

```
<type>(<scope>): <short description>
```

Common types:

| Type | When to use |
|---|---|
| `feat` | A new feature or capability |
| `fix` | A bug fix |
| `docs` | Documentation changes only |
| `chore` | Maintenance (dependency updates, housekeeping) |
| `refactor` | Code restructuring without behaviour change |

Scope is optional but helpful — use the service name or file area, e.g.:

```
fix(quickstatements): add mysqli extension to Dockerfile
docs(elasticsearch): add setup guide
chore(deps): update wdqs image to latest patch
```

Keep the subject line under 72 characters. Use the body for the *why*,
not just the *what*.

---

## Questions

For questions about deployment or configuration, open a
[GitHub Discussion](https://github.com/lucamauri/wikibase-data-services/discussions)
rather than an issue.