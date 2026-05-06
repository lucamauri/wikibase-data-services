#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# wdqs-updater-runUpdate.sh
#
# Modified for https://github.com/lucamauri/wikibase-data-services
# Improved over the original from https://github.com/wmde/wikibase-release-pipeline
#
# Changes from the original:
#   - Removed wait-for-it.sh checks: WDQS readiness is already guaranteed by
#     Docker Compose "depends_on: condition: service_healthy"; Wikibase port 80
#     check was unreliable (Apache answers on 80 with a redirect even when
#     Wikibase is not healthy).
#   - Added validation of UPDATER_DELAY to ensure it is set before proceeding.
#   - Polling interval is now configurable via UPDATER_DELAY env variable
#     (set in .env) rather than relying on the upstream default of 10 seconds.
# -----------------------------------------------------------------------------

set -euo pipefail

# Validate required environment variables
if [ -z "${WIKIBASE_CONCEPT_URI:-}" ]; then
  echo "ERROR: WIKIBASE_CONCEPT_URI is required but is not set."
  exit 1
fi

if [ -z "${UPDATER_DELAY:-}" ]; then
  echo "ERROR: UPDATER_DELAY is required but is not set."
  exit 1
fi

cd /wdqs || exit 1

exec ./runUpdate.sh \
  -h http://"${WDQS_HOST}":"${WDQS_PORT}" -- \
  --wikibaseUrl "${WIKIBASE_SCHEME}"://"${WIKIBASE_HOST}" \
  --conceptUri "${WIKIBASE_CONCEPT_URI}" \
  --entityNamespaces "${WIKIBASE_ENTITY_NAMESPACES}" \
  --apiPath "${WIKIBASE_API_PATH}" \
  --pollDelay "${UPDATER_DELAY}"