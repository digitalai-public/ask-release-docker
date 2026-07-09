# Quick Start - Full local HTTP lab (with-llm, with-postgres, with-release, with-keycloak)

This is the fastest installation path for a full local lab stack over HTTP
(no nginx profile, no TLS setup). It is designed for local functional testing.

What this setup gives you:

- local PostgreSQL (`with-postgres`)
- local LLM service (`with-llm-service`)
- local Release (`with-release`)
- local Keycloak (`with-keycloak`)

What we are intentionally not using here:

- no nginx ingress (`with-nginx` is not enabled)
- no HTTPS certificates
- no internal-CA overlays

How traffic flows in this quick start:

- browser -> `http://release.example.digital.ai.local:5516`
- Release -> Assistant (`RELEASE_ASSISTANT_PUBLIC_URL`)
- Assistant -> Release embedded MCP endpoint `${RELEASE_PUBLIC_URL}${RELEASE_MCP_SERVER_ENDPOINT:-/s/mcp}` (internal docker network)
- Assistant -> local LLM service (`http://llm-service-api:9000/llm`)
- OIDC auth -> local Keycloak over HTTP on `:5080`

## 1) Prepare hostnames

Add to `/etc/hosts` (or Windows hosts file):

```text
127.0.0.1       release.example.digital.ai.local
127.0.0.1       release-assistant.example.digital.ai.local
127.0.0.1       identity.example.digital.ai.local
```

## 2) Create local env file

From repository root:

```bash
cp .env.base .env
```

Set or update these values in `.env`:

```bash
OAUTH2_SCOPES="openid"
OAUTH2_TOKEN_CLIENT_ID=xl-release
OAUTH2_TOKEN_CLIENT_SECRET=ab2088f6-2251-4233-9b22-e24db6a67483

POSTGRES_HOSTNAME=postgres
ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.local
RELEASE_HOSTNAME=release.example.digital.ai.local
IDP_HOSTNAME=identity.example.digital.ai.local

RELEASE_PUBLIC_URL=http://${RELEASE_HOSTNAME}:${RELEASE_HTTP_PORT}
RELEASE_ASSISTANT_PUBLIC_URL=http://${ASSISTANT_HOSTNAME}:${ASSISTANT_PORT}

KEYCLOAK_REALM=xl-platform
KEYCLOAK_LOCAL_ISSUER=http://${IDP_HOSTNAME}:${KEYCLOAK_HTTP_PORT}/realms/${KEYCLOAK_REALM}
OIDC_ISSUER_URI=${KEYCLOAK_LOCAL_ISSUER}

AI_LLM_BASE_URL=http://llm-service-api:${LLM_SERVICE_PORT}/llm
AI_LLM_CHAT_MODEL=replace-me

DAI_ACCOUNT_ID=replace-me
DAI_AUTH_ISSUER_PATTERN=${OIDC_ISSUER_URI}
LLM_SERVICE_DEFAULT_PROVIDER_CONFIG=replace-me-base64
```

Why these values matter:

- `RELEASE_PUBLIC_URL` and `RELEASE_ASSISTANT_PUBLIC_URL` keep Release and Assistant links consistent for browser access.
- `KEYCLOAK_LOCAL_ISSUER` / `OIDC_ISSUER_URI` point all auth validation to local Keycloak.
- `AI_LLM_BASE_URL` switches Assistant to the in-stack LLM service.
- `DAI_*` and `LLM_SERVICE_DEFAULT_PROVIDER_CONFIG` are required by the LLM service tenant/provider bootstrap.
- `RELEASE_MCP_SERVER_ENDPOINT` (defaults to `/s/mcp`) point the Assistant at the embedded MCP endpoint on the in-bridge Release alias.

## 3) Start infrastructure services first

We start stateful dependencies first (Postgres + Keycloak), then continue with
db initialization and app services.

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  up -d postgres keycloak
```

Wait until both are healthy before moving on (especially Keycloak):

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  ps

curl -fsS "http://localhost:${KEYCLOAK_MGMT_PORT:-15090}/health/ready"
```

## 4) Start application services

Now start Release, Assistant, and the LLM API (`llm-service-dbinit` will run as dependecy).

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  up -d llm-service-api release release-assistant
```

## 5) Verify

Check container status:

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  ps
```

Check health endpoints:

```bash
curl -fsS "http://127.0.0.1:${RELEASE_HTTP_PORT:-5516}/s/actuator/health/liveness"
curl -fsS "http://localhost:${ASSISTANT_PORT:-8090}/actuator/health/liveness"
curl -fsS "http://localhost:${LLM_SERVICE_PORT:-9000}/llm/utility/ping"
curl -fsS "http://localhost:${KEYCLOAK_MGMT_PORT:-15090}/health/ready"
```

Notes:

- Some hosts resolve `localhost` to IPv6 first. If Release health returns
  `Empty reply from server`, use `127.0.0.1` as shown above.
- Keycloak readiness is exposed on the management port
  (`KEYCLOAK_MGMT_PORT`, default `15090`), not the public HTTP port.

Open:

`http://release.example.digital.ai.local:5516/`

First login suggestion: use `gandalf/gandalf` (admin-like) or
`alice/alice` (developer-role testing). Full credential list:
`test-lab/README.md` section `2.1`.

## 6) Read logs from all running containers

Use the same compose file set and profiles to stream logs for every active
service in this quick-start stack:

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  logs -f
```

Useful variants:

```bash
# Last 200 lines from all services (no follow)
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  logs --tail=200

# Follow logs for a subset of services
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  logs -f release release-assistant llm-service-api keycloak postgres
```

## 7) Tear down

```bash
docker compose --project-directory . \
  -f docker-compose.yaml \
  -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-release \
  down --remove-orphans
```
