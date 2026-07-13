#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# install-internal-ca.sh - bootstrap the corporate CA into the CORE services'
#                         trust surfaces (uniform per Q5=a).
#
# Usage:
#   ./install-internal-ca.sh <path-to-corporate-ca-bundle.pem>
#
# Outputs (idempotent — re-runs overwrite with the same content):
#   certs/cacerts.jks    JDK truststore for release-assistant
#   certs/ca-bundle.pem  OpenSSL bundle for llm-service-api
#
# Both files are gitignored; they are deployment-specific artifacts, not
# source-of-truth material.
#
# The JDK truststore is built from a local JDK's cacerts when one is
# available (JAVA_HOME, /opt/java/openjdk, /usr/lib/jvm/*,
# /usr/local/openjdk-*) — consistent with the keytool preflight below.
# If no local JDK is found, the script falls back to pulling
# eclipse-temurin:17-jdk-alpine via docker.
#
# After running, restart the CORE services:
#   docker compose -f docker-compose.yaml --profile with-llm-service \
#     restart release-assistant release-mcp llm-service-api
#
# See README.md §28 for the full procedure and lifecycle.
# ----------------------------------------------------------------------------
set -euo pipefail

CA_SRC="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/certs"
JKS="${OUT_DIR}/cacerts.jks"
PEM="${OUT_DIR}/ca-bundle.pem"
JKS_PASS="changeit"
JKS_ALIAS_PREFIX="ask-release-internal-ca"

log() { printf '[install-internal-ca] %s\n' "$*"; }
err() { printf '[install-internal-ca] ERROR: %s\n' "$*" >&2; }

# --- preflight ---------------------------------------------------------------
[ -n "${CA_SRC}" ] || { err "usage: $0 <path-to-corporate-ca-bundle.pem>"; exit 1; }
[ -f "${CA_SRC}" ] || { err "CA file not found: ${CA_SRC}"; exit 1; }
[ -r "${CA_SRC}" ] || { err "CA file not readable: ${CA_SRC}"; exit 1; }

command -v keytool >/dev/null 2>&1 \
    || { err "keytool not found on PATH. Install a JDK (11+)."; exit 1; }
command -v python3 >/dev/null 2>&1 \
    || { err "python3 not found on PATH. Install python3."; exit 1; }
python3 -c "import certifi" 2>/dev/null \
    || { err "python3 'certifi' module not found. pip install certifi."; exit 1; }
command -v docker >/dev/null 2>&1 \
    || { err "docker not found on PATH. Install Docker Engine."; exit 1; }

# --- 1) build the OpenSSL bundle (system CAs + corporate CAs) ---------------
mkdir -p "${OUT_DIR}"
log "building OpenSSL bundle at ${PEM}"
CERTIFI_PATH="$(python3 -c 'import certifi; print(certifi.where())')"
cat "${CERTIFI_PATH}" "${CA_SRC}" > "${PEM}"
PEM_BYTES=$(wc -c < "${PEM}" | tr -d ' ')
log "wrote ${PEM} (${PEM_BYTES} bytes)"

# --- 2) build the JDK truststore (local JDK if available, else docker temurin) -
# Prefer a JDK already on the host (consistent with the `keytool` preflight
# above). Falling back to docker avoids a silent failure when the corporate
# network blocks docker.io, and removes the fragile ${JAVA_HOME} propagation
# through `docker run ... sh -c 'echo "${JAVA_HOME}/..."'`.
resolve_local_cacerts() {
    if [ -n "${JAVA_HOME:-}" ] && [ -f "${JAVA_HOME}/lib/security/cacerts" ]; then
        printf '%s' "${JAVA_HOME}/lib/security/cacerts"; return 0
    fi
    if [ -f "/opt/java/openjdk/lib/security/cacerts" ]; then
        printf '%s' "/opt/java/openjdk/lib/security/cacerts"; return 0
    fi
    local j
    for j in /usr/lib/jvm/*/lib/security/cacerts \
             /usr/local/openjdk-*/lib/security/cacerts; do
        [ -f "$j" ] && { printf '%s' "$j"; return 0; }
    done
    return 1
}

if LOCAL_CACERTS=$(resolve_local_cacerts); then
    log "cloning local JDK cacerts: ${LOCAL_CACERTS}"
    cp "${LOCAL_CACERTS}" "${JKS}"
else
    log "no local JDK cacerts found; pulling eclipse-temurin:17-jdk-alpine"
    if ! docker pull eclipse-temurin:17-jdk-alpine; then
        err "docker pull eclipse-temurin:17-jdk-alpine failed."
        err "Install a JDK locally (keytool is also required by this script)"
        err "or configure your Docker registry to allow Eclipse Temurin pulls."
        exit 1
    fi
    docker run --rm --entrypoint cat eclipse-temurin:17-jdk-alpine \
        /opt/java/openjdk/lib/security/cacerts > "${JKS}"
fi

[ -s "${JKS}" ] || { err "JDK cacerts extraction produced empty file"; exit 1; }
JKS_BYTES=$(wc -c < "${JKS}" | tr -d ' ')
log "cloned ${JKS} (${JKS_BYTES} bytes)"

log "importing corporate CA into JDK truststore"
ALIAS="${JKS_ALIAS_PREFIX}-$(date +%s)"
keytool -importcert -noprompt \
    -alias "${ALIAS}" \
    -file "${CA_SRC}" \
    -keystore "${JKS}" \
    -storepass "${JKS_PASS}" \
    >/dev/null
log "imported CA as alias '${ALIAS}'"

# --- 3) verification ---------------------------------------------------------
log "verifying ${PEM}"
PEM_FIRST=$(head -n 1 "${PEM}")
case "${PEM_FIRST}" in
    "-----BEGIN CERTIFICATE-----"|"-----BEGIN TRUSTED CERTIFICATE-----")
        log "${PEM} starts with a valid PEM header"
        ;;
    *)
        err "${PEM} does not start with a valid PEM header (got: ${PEM_FIRST})"
        exit 1
        ;;
esac

log "verifying ${JKS}"
keytool -list -keystore "${JKS}" -storepass "${JKS_PASS}" \
    >/dev/null 2>&1 \
    || { err "JKS failed to load: ${JKS}"; exit 1; }
keytool -list -keystore "${JKS}" -storepass "${JKS_PASS}" \
    | grep -F "${ALIAS}" >/dev/null \
    || { err "JKS does not contain alias ${ALIAS}"; exit 1; }
log "${JKS} loaded and contains alias ${ALIAS}"

chmod 0644 "${JKS}" "${PEM}"
log "set 0644 permissions on ${JKS} and ${PEM}"

log "done. activate the internal-CA trust overlay on your next docker compose run:"
log "  # CORE-only stack (release-assistant, release-mcp, llm-service-api)"
log "  docker compose \\"
log "    -f docker-compose.yaml \\"
log "    -f docker-compose.with-internal-ca.yaml \\"
log "    --env-file .env.base --env-file .env-local \\"
log "    --profile with-llm-service \\"
log "    up -d"
log "  # Full end-to-end (CORE + TEST); add the test overlay for the test release service"
log "  docker compose \\"
log "    --project-directory . \\"
log "    -f docker-compose.yaml \\"
log "    -f test-lab/docker-compose.yaml \\"
log "    -f docker-compose.with-internal-ca.yaml \\"
log "    -f test-lab/docker-compose.with-internal-ca.yaml \\"
log "    --env-file .env.base --env-file .env-local \\"
log "    --profile with-postgres --profile with-release \\"
log "    --profile with-keycloak --profile with-nginx \\"
log "    --profile with-llm-service \\"
log "    up -d"
