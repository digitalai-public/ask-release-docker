---
name: ask-release-quick-start
description: Use when setting up a new Ask Release local lab instance with test-lab/QUICK-START.md, including env collection, docker compose run order, and health verification.
---

# Ask Release Quick Start

Use this skill ONLY for setting up or validating the local HTTP lab stack documented in `test-lab/QUICK-START.md`.

## Inputs to collect first

Ask for missing env values before starting containers:

- `AI_LLM_CHAT_MODEL`
- `DAI_ACCOUNT_ID` (must be UUID: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- `LLM_SERVICE_DEFAULT_PROVIDER_CONFIG` (base64 JSON)

If the user provides provider credentials instead of base64, generate base64 from provider JSON and write it to `.env`.

## Setup workflow

Run from repository root.

1. Prepare `.env`:

```bash
cp .env.base .env
```

2. Ensure Quick Start overrides are present in `.env`:

- `POSTGRES_HOSTNAME=postgres`
- `ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.local`
- `RELEASE_HOSTNAME=release.example.digital.ai.local`
- `IDP_HOSTNAME=identity.example.digital.ai.local`
- `RELEASE_PUBLIC_URL=http://${RELEASE_HOSTNAME}:${RELEASE_HTTP_PORT}`
- `RELEASE_ASSISTANT_PUBLIC_URL=http://${ASSISTANT_HOSTNAME}:${ASSISTANT_PORT}`
- `KEYCLOAK_REALM=xl-platform`
- `KEYCLOAK_LOCAL_ISSUER=http://${IDP_HOSTNAME}:${KEYCLOAK_HTTP_PORT}/realms/${KEYCLOAK_REALM}`
- `OIDC_ISSUER_URI=http://${IDP_HOSTNAME}:${KEYCLOAK_HTTP_PORT}/realms/xl-platform`
- `DAI_AUTH_ISSUER_PATTERN=http://${IDP_HOSTNAME}:${KEYCLOAK_HTTP_PORT}/realms/xl-platform`
- `AI_LLM_BASE_URL=http://llm-service-api:${LLM_SERVICE_PORT}/llm`

3. Start infra first:

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  up -d postgres keycloak
```

4. Wait for readiness:

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  ps

curl -fsS "http://localhost:${KEYCLOAK_MGMT_PORT:-15090}/health/ready"
```

5. Run db init:

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  up llm-service-dbinit
```

6. Start app services:

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  up -d llm-service-api release release-assistant
```

## Verify

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  ps

curl -fsS "http://127.0.0.1:${RELEASE_HTTP_PORT:-5516}/s/actuator/health/liveness"
curl -fsS "http://localhost:${ASSISTANT_PORT:-8090}/actuator/health/liveness"
curl -fsS "http://localhost:${LLM_SERVICE_PORT:-9000}/llm/utility/ping"
curl -fsS "http://localhost:${KEYCLOAK_MGMT_PORT:-15090}/health/ready"
```

Open:

- `http://release.example.digital.ai.local:5516/`

## Teardown

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  down --remove-orphans
```
