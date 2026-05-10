#!/usr/bin/env bash
# =============================================================================
# wdqs-updater-runUpdate.sh
#
# Custom replacement for the upstream /runUpdate.sh from:
#   https://github.com/wmde/wikibase-release-pipeline
#
# Mounted into the wdqs-updater container via docker-compose.yml:
#   volumes:
#     - ./config/wdqs-updater-runUpdate.sh:/runUpdate.sh
#
# WHY THIS SCRIPT REPLACES THE UPSTREAM VERSION
# ----------------------------------------------
# Three changes were needed for a clean self-hosted deployment:
#
#   1. REMOVED: wait-for-it.sh dependency checks
#      The upstream script uses wait-for-it.sh to poll WDQS (port 9999) and
#      Wikibase (port 80) before starting the updater.
#      - The WDQS check is redundant: Docker Compose "depends_on: condition:
#        service_healthy" already guarantees wdqs is healthy before this
#        container starts. Polling again just adds startup delay.
#      - The Wikibase port-80 check is unreliable: Apache answers on port 80
#        with a redirect (301/302) even when Wikibase itself is not yet ready.
#        A successful TCP connection to port 80 does not mean the API works.
#
#   2. ADDED: UPDATER_DELAY environment variable
#      The upstream script hardcodes a 10-second polling interval.
#      UPDATER_DELAY makes this configurable via .env so operators can tune
#      it for their wiki's edit frequency without modifying this script.
#      Unit: SECONDS. Set in .env; validated below before use.
#
#   3. IMPROVED: set -euo pipefail and exec
#      Added strict error handling and clean process replacement — see inline
#      comments below for details.
# =============================================================================

# -----------------------------------------------------------------------------
# Strict mode
# -----------------------------------------------------------------------------
# -e : exit immediately if any command returns a non-zero exit code.
#      Prevents silent failures where a setup step fails but the script
#      continues and starts the updater in a broken state.
# -u : treat unset variables as errors. Catches typos in variable names
#      (e.g. ${WIKIBASE_HOS} instead of ${WIKIBASE_HOST}) that would
#      otherwise silently expand to an empty string.
# -o pipefail : if any command in a pipeline fails, the whole pipeline
#      returns a failure exit code (not just the last command). Important
#      for any future changes that might add piped commands.
# -----------------------------------------------------------------------------
set -euo pipefail

# -----------------------------------------------------------------------------
# Validate required environment variables
# -----------------------------------------------------------------------------
# WIKIBASE_CONCEPT_URI and UPDATER_DELAY are validated explicitly because:
#   - A missing or malformed WIKIBASE_CONCEPT_URI causes the Munger to throw
#     BadSubjectException on every entity update — Blazegraph gets no data.
#   - A missing UPDATER_DELAY would fall through to the --pollDelay argument
#     as an empty string, causing the Java process to fail with an unhelpful
#     argument parsing error.
#
# WDQS_HOST and WDQS_PORT are NOT validated here — they are set by the
# upstream image entrypoint with safe defaults and are always present.
# -----------------------------------------------------------------------------
if [ -z "${WIKIBASE_CONCEPT_URI:-}" ]; then
  echo "ERROR: WIKIBASE_CONCEPT_URI is required but is not set."
  echo "       It should be assembled in docker-compose.yml as:"
  echo "       \${WIKIBASE_SCHEME}://\${WIKIBASE_HOST}/"
  echo "       Do NOT set it in .env — see docs/adr-concept-uri-assembly.md"
  exit 1
fi

if [ -z "${UPDATER_DELAY:-}" ]; then
  echo "ERROR: UPDATER_DELAY is required but is not set."
  echo "       Set it in .env (unit: seconds, e.g. UPDATER_DELAY=60)."
  exit 1
fi

# -----------------------------------------------------------------------------
# Change to the WDQS working directory
# -----------------------------------------------------------------------------
# runUpdate.sh (the Blazegraph updater JAR wrapper) must be run from /wdqs
# because it uses relative paths to find the JAR and its configuration.
# The || exit 1 is belt-and-suspenders given set -e, but makes the intent
# explicit: if this directory doesn't exist, something is badly wrong.
# -----------------------------------------------------------------------------
cd /wdqs || exit 1

# -----------------------------------------------------------------------------
# Start the updater
# -----------------------------------------------------------------------------
# exec replaces this shell process with the Java updater process.
# Without exec, this script would remain as a parent process wrapping the
# updater. Using exec means:
#   - Docker sees the updater as PID 1 in the container (cleaner signal
#     handling — SIGTERM from "docker stop" reaches the Java process directly)
#   - No unnecessary shell process sitting idle for the container's lifetime
#
# Arguments:
#   -h http://${WDQS_HOST}:${WDQS_PORT}
#       The internal HTTP address of the Blazegraph container. The updater
#       uses this to push RDF updates directly into Blazegraph.
#
#   --wikibaseUrl
#       Base URL of the Wikibase instance (scheme + host only, no path).
#       The updater appends the API path itself.
#
#   --conceptUri
#       The canonical URI prefix for Wikibase entities (e.g. https://data.example.org/).
#       Must end with a trailing slash and must NOT include /entity/.
#       Adding /entity/ here causes BadSubjectException in the Munger.
#
#   --entityNamespaces
#       Comma-separated MediaWiki namespace IDs for entity types.
#       Standard self-hosted Wikibase: 120 (Item), 122 (Property).
#       Do NOT use 146 — that is Wikidata-specific.
#
#   --apiPath
#       Path to api.php on the Wikibase host (e.g. /w/api.php).
#
#   --pollDelay
#       How often (in seconds) to poll Wikibase for new changes.
#       Comes from UPDATER_DELAY in .env.
# -----------------------------------------------------------------------------
exec ./runUpdate.sh \
  -h "http://${WDQS_HOST}:${WDQS_PORT}" -- \
  --wikibaseUrl "${WIKIBASE_SCHEME}://${WIKIBASE_HOST}" \
  --conceptUri "${WIKIBASE_CONCEPT_URI}" \
  --entityNamespaces "${WIKIBASE_ENTITY_NAMESPACES}" \
  --apiPath "${WIKIBASE_API_PATH}" \
  --pollDelay "${UPDATER_DELAY}"