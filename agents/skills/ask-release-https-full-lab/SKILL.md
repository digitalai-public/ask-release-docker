---
name: ask-release-https-full-lab
description: Use when installing Ask Release recipe 8.4 (https, with-llm-service, with-postgres, with-release, with-keycloak), including cert generation, internal-CA overlay, compose run order, and health checks.
---

# Ask Release HTTPS Full Lab (Recipe 8.4)

Use this skill ONLY for `test-lab/README.md` recipe `8.4 https, with-llm, with-postgres, with-release, with-keycloak`.

## Inputs to collect first

Treat repository compose/env defaults as valid. Do not run extra preflight checks for image variables or other optional env keys.

Collect these user-specific values before starting containers:

- `AI_LLM_CHAT_MODEL`
- `DAI_ACCOUNT_ID`
- `LLM_SERVICE_DEFAULT_PROVIDER_CONFIG` (base64 JSON)

Everything else should come from `.env.base` plus the recipe overrides below.

If the user provides provider credentials instead of base64, generate base64 from provider JSON and write it to `.env`.

## Setup workflow

Run from repository root.

1) Prepare `.env`:

```bash
cp .env.base .env
```

2) Add host mappings:

```text
127.0.0.1       release.example.digital.ai.nginx
127.0.0.1       release-assistant.example.digital.ai.nginx
127.0.0.1       identity.example.digital.ai.nginx
```

3) Ensure these overrides are present in `.env`:

- `NGINX_RELEASE_HOSTNAME=release.example.digital.ai.nginx`
- `NGINX_ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.nginx`
- `NGINX_IDP_HOSTNAME=identity.example.digital.ai.nginx`
- `RELEASE_PUBLIC_URL=https://${NGINX_RELEASE_HOSTNAME}:${NGINX_HTTPS_PORT}`
- `RELEASE_ASSISTANT_PUBLIC_URL=https://${NGINX_ASSISTANT_HOSTNAME}:${NGINX_HTTPS_PORT}`
- `OAUTH2_SCOPES="openid"`
- `OAUTH2_TOKEN_CLIENT_ID=xl-release`
- `OAUTH2_TOKEN_CLIENT_SECRET=ab2088f6-2251-4233-9b22-e24db6a67483`
- `KEYCLOAK_PROTOCOL=https`
- `KEYCLOAK_HOSTNAME=${NGINX_IDP_HOSTNAME}`
- `KEYCLOAK_PORT=${NGINX_HTTPS_PORT}`
- `KEYCLOAK_REALM=xl-platform`
- `KEYCLOAK_LOCAL_ISSUER=${KEYCLOAK_PROTOCOL}://${NGINX_IDP_HOSTNAME}:${NGINX_HTTPS_PORT}/realms/${KEYCLOAK_REALM}`
- `OIDC_ISSUER_URI=${KEYCLOAK_LOCAL_ISSUER}`
- `AI_LLM_BASE_URL=http://llm-service-api:${LLM_SERVICE_PORT}/llm`
- `DAI_AUTH_ISSUER_PATTERN=${OIDC_ISSUER_URI}`

4) Generate local self-signed certs for nginx:

```bash
SAN="DNS:release.example.digital.ai.nginx,DNS:release-assistant.example.digital.ai.nginx,DNS:identity.example.digital.ai.nginx"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout test-lab/nginx/certs/tls.key -out test-lab/nginx/certs/tls.crt \
    -subj "/CN=ask-release" \
    -addext "subjectAltName=${SAN}"
```

5) Build trust artifacts consumed by internal-CA overlays:

```bash
./install-internal-ca.sh test-lab/nginx/certs/tls.crt
```

6) Start the full stack:

```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml \
  -f docker-compose.with-internal-ca.yaml \
  -f test-lab/docker-compose.yaml \
  -f test-lab/docker-compose.with-internal-ca.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-nginx --profile with-release \
  up -d postgres llm-service-api keycloak nginx release release-assistant
```

## Verify

1) Check service status:

```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml \
  -f docker-compose.with-internal-ca.yaml \
  -f test-lab/docker-compose.yaml \
  -f test-lab/docker-compose.with-internal-ca.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-nginx --profile with-release \
  ps
```

2) Check endpoints through nginx:

```bash
curl -kfsS "https://release-assistant.example.digital.ai.nginx:5443/actuator/health/liveness"
curl -kfsS "https://release.example.digital.ai.nginx:5443/s/actuator/health/liveness"
curl -kfsS "https://identity.example.digital.ai.nginx:5443/realms/xl-platform/.well-known/openid-configuration"
```

Before opening Release in a browser, open the assistant health URL and accept the certificate warning for the self-signed cert:

- `https://release-assistant.example.digital.ai.nginx:5443/actuator/health`

Open:

- `https://release.example.digital.ai.nginx:5443/`

## Teardown

```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml \
  -f docker-compose.with-internal-ca.yaml \
  -f test-lab/docker-compose.yaml \
  -f test-lab/docker-compose.with-internal-ca.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-nginx --profile with-release \
  down --remove-orphans
# remove db data
docker volume rm ask-release-postgres-data
# clean generated files except .env
git clean -fdx -e . env
```
