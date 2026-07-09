# Ask Release Docker - Test/lab deployment guide

> **Lab-only documentation.** This document covers every lab profile the
> repository supports: `--profile with-keycloak`, `--profile with-release`,
> `--profile with-postgres`, `--profile with-nginx`, and any combination
> of them. For the production deployment documentation (CORE compose,
> external Postgres / Release / IdP, secure connectivity, sizing,
> backup/DR, monitoring, private-CA trust), see
> [README.md](../README.md).
>
> The split mirrors the compose-file split:
>
> - `docker-compose.yaml` (root)         - CORE services (release-assistant, llm-service)
> - `test-lab/docker-compose.yaml`           - TEST/lab services (keycloak, nginx, postgres, in-stack Release)
>
> All commands below assume you start from the repository root and pass
> `--project-directory .` so Compose resolves `extends` paths correctly
> when the two compose files are combined.

## 1) Overview

The `test-lab/` directory ships the lab infrastructure that pairs with the
CORE compose to give you a fully self-contained end-to-end Ask Release
stack on a single host. Every lab service is opt-in: nothing in
`test-lab/` starts until you add its `with-*` profile to a `docker compose`
command.

| Profile | Service | Use case |
|---|---|---|
| `with-postgres` | `postgres` | Local PostgreSQL for non-production / PoC runs. Drops the customer's managed-Postgres requirement. |
| `with-release` | `release` | Local Digital.ai Release container. Drops the customer's existing-Release requirement. |
| `with-keycloak` | `keycloak` | Local Keycloak IdP preloaded with the `xl-platform` realm. Drops the customer's enterprise-IdP requirement. |
| `with-nginx` | `nginx` | Optional reverse proxy that terminates TLS in front of the public-facing services (Assistant, Release, Keycloak login). Drops the "place a corporate LB in front" requirement for local labs. |
| `with-llm-service` | `llm-service-api`, `llm-service-dbinit` | Local LLM Service. Drops the customer's external-LLM-endpoint requirement. (`with-llm-service` lives in the CORE compose; it is included here because every lab recipe that needs an LLM endpoint uses it.) |

Combining them:

```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml \
  [-f test-lab/docker-compose.yaml] \
  [-f docker-compose.with-internal-ca.yaml] \
  --profile <profiles> \
  <command>
```

Compose reads `.env` from the project root implicitly - no `--env-file`
flag is needed. The `.env` file is gitignored; copy it from `.env.base`
and edit per host.

If you only want to run the test stack (e.g. against an existing
external Release / postgres), drop `-f docker-compose.yaml`. If you only
want the core stack (e.g. for production-like deploys against external
IdP, DB, Release), drop `-f test-lab/docker-compose.yaml`.

Add `-f docker-compose.with-internal-ca.yaml` (and
`-f test-lab/docker-compose.with-internal-ca.yaml` when the test stack is in
use) only when you need internal corporate CA trust (IdP / Release /
LLM endpoints whose certs are signed by a private chain). Requires
`certs/cacerts.jks` and `certs/ca-bundle.pem` at the repo root -
generate with `./install-internal-ca.sh <corp-ca-bundle.pem>` (see
[README.md §28](../README.md#28-private-ca--self-signed-trust)). Without
the overlay, the CORE and test services use the system default trust
stores.

For the production deployment paths (external Postgres / Release / IdP
each managed by the customer), see [README.md §8.1-§8.3](../README.md#8-quick-start).

For a shorter guided install of the full local HTTP lab stack
(`with-llm-service`, `with-postgres`, `with-release`, `with-keycloak`),
see [QUICK-START.md](QUICK-START.md).

## 2) Local Keycloak IdP (--profile with-keycloak)

The `with-keycloak` profile starts a local Keycloak container preloaded
with a development realm (`test-lab/keycloak/data/xl-platform-realm.json`).
Use this profile when you want to bring up an end-to-end Ask Release
stack without depending on an external IdP. Requires the TEST compose
file: `-f docker-compose.yaml -f test-lab/docker-compose.yaml`.

What the profile activates:

| Service | Container name | Notes |
|---|---|---|
| `keycloak` | `ask-release-keycloak` | Local IdP, realm preloaded from `test-lab/keycloak/data/xl-platform-realm.json` |

Other services (`release-assistant`, `llm-service-api`, `release`)
automatically pick up the local Keycloak issuer when their OIDC env
vars are pointed at `KEYCLOAK_LOCAL_ISSUER` - no separate `-local`
service variants are needed.

Required env override (in your layered `.env`):

```bash
# Point Assistant, LLM service, and (optional) Release at the local Keycloak
OIDC_ISSUER_URI=${KEYCLOAK_LOCAL_ISSUER}
DAI_AUTH_ISSUER_PATTERN=${KEYCLOAK_LOCAL_ISSUER}
# Release OIDC vars default to OIDC_ISSUER_URI when not overridden
# When using the local LLM service, also point the Assistant at it:
# AI_LLM_BASE_URL=http://llm-service-api:9000
# AI_LLM_CHAT_MODEL=<model name returned by the local LLM service>
```

Quick start (local Keycloak + local LLM, no Release):

```bash
# Start Keycloak first; other services wait for it to be healthy.
docker compose --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-keycloak up -d keycloak

# When combining with --profile with-llm-service, run the one-shot DB init
docker compose --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-keycloak --profile with-llm-service up llm-service-dbinit

# Start the core services; release-assistant picks up OIDC_ISSUER_URI +
# AI_LLM_BASE_URL from the layered .env.
docker compose --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-keycloak --profile with-llm-service up -d \
    llm-service-api release-assistant
```

Full local lab (Keycloak + Release + LLM + Postgres):

```bash
docker compose --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-keycloak --profile with-release --profile with-postgres up -d postgres keycloak
docker compose --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-keycloak --profile with-release --profile with-postgres --profile with-llm-service up llm-service-dbinit
docker compose --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-keycloak --profile with-release --profile with-postgres --profile with-llm-service up -d \
    llm-service-api release-assistant release
```

First login suggestion: use `gandalf/gandalf` (admin-like roles) or
`alice/alice` (developer-role testing).

Notes:

- Default admin credentials for the local Keycloak are `admin` / `admin`
  (inlined as `${KEYCLOAK_ADMIN_USER:-admin}` /
  `${KEYCLOAK_ADMIN_PASSWORD:-admin}` in `test-lab/keycloak/compose.yaml`).
  Override in your layered `.env` for any non-lab use.
- Keycloak uses an H2 in-memory database by default. To persist data
  across restarts, mount a host volume or external DB and set
  `DB_VENDOR` accordingly.
- The local Keycloak realm (`xl-platform`) ships with sample users,
  clients, and roles for development. Override by editing
  `test-lab/keycloak/data/xl-platform-realm.json` or replacing the realm
  file.
- `release-assistant` reads `OIDC_ISSUER_URI`, `AI_LLM_BASE_URL`, and
  `AI_LLM_CHAT_MODEL` from env (substituted via `${VAR:default}` in
  `release-assistant/config/release-ai-assistant-config.yaml`).
  Defaults target the Digital.ai SaaS LLM endpoint, so override those
  two vars in your `.env` whenever you want to hit a different endpoint
  (local LLM service, external gateway, etc.).

### 2.1 Default Keycloak login users (preloaded)

When `with-keycloak` is enabled, the `xl-platform` realm is imported from
`test-lab/keycloak/data/xl-platform-realm.json` and ships with preloaded
test users. In this lab setup, each user password equals the username.

| Username | Password |
|---|---|
| `alice` | `alice` |
| `bilbo` | `bilbo` |
| `bob` | `bob` |
| `carol` | `carol` |
| `elrond` | `elrond` |
| `eve` | `eve` |
| `frodo` | `frodo` |
| `gandalf` | `gandalf` |
| `root` | `root` |
| `sauron` | `sauron` |

Recommended demo users:

- `gandalf/gandalf` for admin-like role testing
- `alice/alice` for developer-role testing

Lab-only warning: these credentials are for local testing only and must not
be used in shared, staging, or production environments.

## 3) Local Digital.ai Release (--profile with-release)

When the optional local Release container is started (requires
`-f test-lab/docker-compose.yaml`):

- `test-lab/release/conf/` is bind-mounted into the release container at
  `/opt/xebialabs/xl-release-server/conf`, overlaying the image's
  default config so the shipped `xl-release.conf` is used instead of
  the image default.
- The shipped `test-lab/release/default-conf/xl-release.conf.template` is
  mounted read-only into the image's `default-conf/` path and provides
  the HOCON template the container resolves at startup.
  On first start, the container writes the resolved config into
  `test-lab/release/conf/xl-release.conf` (under the bind mount). To override
  defaults, copy the template into `test-lab/release/conf/xl-release.conf`
  and edit it. The template itself covers blocks not exposed via the
  official `xebialabs/xl-release` image environment variables (see
  [Environment variables](https://xebialabs.github.io/xl-docker-images/docs/manual/environment-variables)).

Two blocks are required for Ask Release to work end-to-end:

- `xl.features.ai.assistant-url` and `xl.features.ai.enabled=true` so
  the Release UI exposes the Ask Release chat and routes to the
  Assistant container.
- `xl.security.auth.providers.oidc.*` so users authenticate against
  your IdP. The `scopes` list **must** include `dai-svc` so the issued
  user token carries the `dai-svc` audience the LLM service validates.

The HOCON file uses `${?VAR}` substitution so values are resolved
directly from the release container's environment at startup. No init
container, no `envsubst`, no template pre-rendering step is required.

Runtime artifacts (`*.lic`, `*.jceks`, `*.xml`, `*.yaml`, `*.properties`,
`*.policy`, `*.vm`, `xlr-*.conf`, `xl-release-server.conf`) are excluded
via `test-lab/release/conf/.gitignore` so they are never committed.

Env vars consumed by the template (defaults shipped via
`test-lab/release/compose.yaml`):

| Env var | Purpose |
|---|---|
| `RELEASE_ASSISTANT_PUBLIC_URL` | URL of the Ask Release Assistant (default: `https://release-assistant.example.digital.ai:8090`) |
| `RELEASE_OIDC_REDIRECT_URI` | OIDC redirect URI used for both login and post-logout (default: `https://release-assistant.example.digital.ai:5516/oidc-login`) |

`RELEASE_OIDC_CLIENT_ID` and `RELEASE_OIDC_CLIENT_SECRET` default to
`OAUTH2_TOKEN_CLIENT_ID` and `OAUTH2_TOKEN_CLIENT_SECRET` (same IdP
client registration). `RELEASE_OIDC_ISSUER` defaults to
`OIDC_ISSUER_URI` (same IdP realm). `RELEASE_OIDC_KEY_RETRIEVAL_URI`,
`RELEASE_OIDC_ACCESS_TOKEN_URI`, `RELEASE_OIDC_USER_AUTHORIZATION_URI`,
and `RELEASE_OIDC_LOGOUT_URI` are derived from `OIDC_ISSUER_URI` via
the `${VAR:-default}` chain in `test-lab/release/compose.yaml`
(Keycloak-style: `${issuer}/protocol/openid-connect/{certs,token,auth,logout}`).
`RELEASE_OIDC_POST_LOGOUT_REDIRECT_URI` defaults to
`RELEASE_OIDC_REDIRECT_URI`. Override any of them only if the local
Release uses a different IdP / client / layout than the Assistant.

Before starting the local Release profile
(`docker compose -f docker-compose.yaml -f test-lab/docker-compose.yaml --profile with-release ...`):

1. Set the `RELEASE_OIDC_*` and `RELEASE_ASSISTANT_PUBLIC_URL` vars in
   your layered `.env` for your environment.
2. Drop your `xl-release-license.lic` into `test-lab/release/conf/`
   (excluded by `test-lab/release/conf/.gitignore`).
3. Do not commit real client secrets to `.env` - use a secret manager
   / `docker secrets` in production.

The bind mount overrides the image's default `xl-release.conf`. All
other configuration comes from the `release` image defaults and the env
vars in your layered `.env`. To restore a clean config after edits:
`rm -f test-lab/release/conf/xl-release.conf && docker compose restart release`.

## 4) Optional reverse proxy (--profile with-nginx)

The `with-nginx` profile adds an nginx container that terminates TLS and
proxies the Ask Release services that have a public vhost (Assistant by
default, plus optionally Release / Keycloak) over HTTPS on a single
host port (default `:5443`). It is a thin, opinionated replacement for
the "place a reverse proxy in front" pattern recommended for
production. Requires `-f test-lab/docker-compose.yaml`.

What the profile activates:

| Service | Container name | Notes |
|---|---|---|
| `nginx` | `ask-release-nginx` | Public ingress; vhost-routes to Assistant, LLM service, and (optionally) Release / Keycloak |

Required setup before first start:

1. Provide a TLS cert + key. Drop them under `test-lab/nginx/certs/`:

   ```text
   test-lab/nginx/certs/tls.crt    # PEM cert (full chain)
   test-lab/nginx/certs/tls.key    # matching private key
   ```

   The cert MUST cover every vhost hostname the operator wants to serve.
   The default vhost list includes the `*.example.digital.ai.local`
   aliases baked into the per-service compose files, plus any public
   FQDNs set via `ASSISTANT_HOSTNAME`, `RELEASE_HOSTNAME`,
   `IDP_HOSTNAME` in `.env`.

   Quick self-signed example for local labs only:

    ```bash
    SAN="DNS:release.example.digital.ai.local,DNS:release-assistant.example.digital.ai.local,DNS:identity.example.digital.ai.local"
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
        -keyout test-lab/nginx/certs/tls.key -out test-lab/nginx/certs/tls.crt \
        -subj "/CN=ask-release" \
        -addext "subjectAltName=${SAN}"
    ```

   **Important (self-signed certs in local lab):** browsers do not trust
   self-signed certs by default. On first access, open the HTTPS URL for
   each exposed vhost (Assistant, and Release/IdP if enabled) and accept
   the certificate warning in the browser to proceed. Use this only for
   local test-lab environments.

2. Optionally set the public FQDNs in `.env`:

   ```bash
   ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.local
   RELEASE_HOSTNAME=release.example.digital.ai.local # only with --profile with-release
   IDP_HOSTNAME=identity.example.digital.ai.local # only with --profile with-keycloak
   ```

3. Start the stack with the `with-nginx` profile added to whichever
   deployment mode is in use (always pass
   `-f docker-compose.yaml -f test-lab/docker-compose.yaml` and
   `--project-directory .`):

   ```bash
# Default mode + nginx ingress (core + test compose, with-llm-service profile)
    docker compose --project-directory . \
      -f docker-compose.yaml -f test-lab/docker-compose.yaml \
      --profile with-llm-service --profile with-nginx up llm-service-dbinit
    docker compose --project-directory . \
      -f docker-compose.yaml -f test-lab/docker-compose.yaml \
      --profile with-llm-service --profile with-nginx up -d \
        llm-service-api release-assistant nginx

    # Core-only (no local LLM) + nginx ingress
    docker compose --project-directory . \
      -f docker-compose.yaml -f test-lab/docker-compose.yaml \
      --profile with-nginx up -d release-assistant nginx

    # Full local lab (Keycloak + Release + LLM) + nginx ingress
    docker compose --project-directory . \
      -f docker-compose.yaml -f test-lab/docker-compose.yaml \
      --profile with-keycloak --profile with-release --profile with-postgres \
      --profile with-llm-service --profile with-nginx up -d \
      postgres keycloak
    docker compose --project-directory . \
      -f docker-compose.yaml -f test-lab/docker-compose.yaml \
      --profile with-keycloak --profile with-release --profile with-postgres \
      --profile with-llm-service --profile with-nginx up llm-service-dbinit
     docker compose --project-directory . \
       -f docker-compose.yaml -f test-lab/docker-compose.yaml \
       --profile with-keycloak --profile with-release --profile with-postgres \
       --profile with-llm-service --profile with-nginx up -d \
       llm-service-api release-assistant release nginx
     ```

First login suggestion when local Keycloak is active: `gandalf/gandalf`
or `alice/alice` (see §2.1).

4. Verify:

   ```bash
   # End-to-end through nginx (replace <hostname> with the cert SAN or one of the *_HOSTNAME values)
   # The Assistant is the only core service fronted by a public nginx vhost by default.
   curl -kfsS "https://<assistant-hostname>/actuator/health/liveness"
   # Add the Release / Keycloak vhost curls here when their profiles are active
   # and the matching vhost SANs are on the cert.
   ```

When the profile is active, `RELEASE_PUBLIC_URL` (and
`RELEASE_ASSISTANT_PUBLIC_URL` when the local Release is in use) must
point at the nginx-fronted FQDN (e.g.
`RELEASE_PUBLIC_URL=https://release.example.com`). The default local-lab
FQDNs (`https://release.example.digital.ai.local:5516`, etc.) keep
working unchanged when the `*.example.digital.ai.local` SANs are
present on the cert.

## 5) Reverse proxy / HTTPS ingress (production-grade nginx)

The `with-nginx` profile adds an nginx container that terminates TLS in
front of every Ask Release service. It is a turnkey alternative to
placing an external load balancer or proxy in front of the stack.
Lives under `test-lab/nginx/`; requires `-f test-lab/docker-compose.yaml`.

**Architecture:**

```text
   internet --HTTPS:5443--> [nginx] --HTTP--> [release-assistant :8090]
                              |---HTTP--> [release           :5516]  (only --profile with-release)
                              |---HTTP--> [keycloak          :8080]  (only --profile with-keycloak)
```

The Release MCP and local LLM service have no public vhost: they are
reached only by the Assistant over the internal `ask-release-net`
bridge, so the nginx proxy does not need to route to them. (The MCP
endpoint is embedded inside Digital.ai Release at
`${RELEASE_PUBLIC_URL}${RELEASE_MCP_SERVER_ENDPOINT:-/s/mcp}`; the
nginx proxy fronts the Release UI vhost only.)

**Activate:**

```bash
# 1. Drop TLS cert + key at test-lab/nginx/certs/tls.crt and test-lab/nginx/certs/tls.key
#    (cert must cover every vhost you intend to serve)

# 2. Add the profile to whichever deployment mode you use, e.g. default mode:
docker compose --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-llm-service --profile with-nginx up -d \
    llm-service-api release-assistant nginx

# 3. Verify
docker compose --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-nginx ps nginx
```

**What the nginx overlay applies:**

| Setting | Default compose | with-nginx profile |
|---|---|---|
| TLS termination point | each service exposes its own (no TLS by default) | nginx on `:5443`; backends stay HTTP on the internal bridge |
| Public port | one per service (8090, 8000, 9000, ...) | single HTTPS port (`5443`) fronting all vhosts |
| `HSTS`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` | not set by default | set on every HTTPS vhost |
| WebSocket / SSE | depends on each service's own listener | nginx forwards `Upgrade`/`Connection` (Assistant Vaadin push, Release UI WS) |
| Upstream re-resolution | n/a | enabled (Docker DNS via `resolver 127.0.0.11` + `resolve` flag) so container restarts do not stale-pin IPs |
| `OCSP stapling` | n/a | enabled (cert chain is required; see Cert format below) |

**Vhost mapping (default):**

| Public hostname (vhost) | Backend service | Backend port | Activated by |
|---|---|---:|---|
| `release-assistant.example.digital.ai.local` (+ `ASSISTANT_HOSTNAME` if set) | `release-assistant` | 8090 | always |
| `release.example.digital.ai.local` (+ `RELEASE_HOSTNAME` if set) | `release` | 5516 | `--profile with-release` |
| `identity.example.digital.ai.local` (+ `IDP_HOSTNAME` if set) | `keycloak` | 8080 | `--profile with-keycloak` |

**Cert format (required):**

```text
test-lab/nginx/certs/tls.crt    # full chain (leaf + intermediates) as PEM
test-lab/nginx/certs/tls.key    # matching private key, PEM
```

- Single cert with SANs for every vhost is the typical production pattern.
- A wildcard cert covering `*.example.digital.ai.local` is sufficient
  for the local-lab FQDNs out of the box.
- For OCSP stapling to work the issuer cert must be in the chain
  portion of `tls.crt`.

**Network flows (additions when `with-nginx` is active):**

| Source | Destination | Port | Protocol | Required for |
|---|---|---:|---|---|
| User browser | nginx | 5443 | HTTPS | All Ask Release UI / API traffic (Assistant, Release, Keycloak login) |
| nginx | release-assistant | 8090 | HTTP | Assistant vhost proxy |
| nginx | release | 5516 | HTTP | Release vhost proxy (with `--profile with-release`) |
| nginx | keycloak | 8080 | HTTP | Keycloak vhost proxy (with `--profile with-keycloak`) |

These flows stay on the internal `ask-release-net` bridge and do not
need additional firewall rules. The host-level publish is the single
`:5443` on the nginx container. The LLM service is reached by
the Assistant over the internal bridge, not via the public nginx
vhosts. (The embedded MCP endpoint lives on the Release image at
`${RELEASE_PUBLIC_URL}${RELEASE_MCP_SERVER_ENDPOINT:-/s/mcp}` and is
reached by the Assistant over the same internal bridge.)

**Production recommendations when using `with-nginx`:**

1. Pair with the CORE hardening overlay
   (`docker-compose.override.yaml.example`) so backends bind to
   loopback (`127.0.0.1:`) and are only reachable via the docker
   network alias used by nginx.
2. Pair with the TEST hardening overlay
   (`test-lab/docker-compose.override.yaml.example`) if running the
   combined lab stack.
3. Issue a real cert from your internal CA or a public CA. Pin the
   cert to the configured vhost SANs; do not use the self-signed sample
   cert in production.
4. Set `RELEASE_PUBLIC_URL`, `RELEASE_ASSISTANT_PUBLIC_URL` (when the
   local Release is in use), and the local Keycloak FQDN to the
   nginx-fronted public URL (port 5443, https) so the Assistant, the
   embedded MCP endpoint (on the Release base URL), the Release UI, and
   the IdP see consistent issuer/audience values.
5. Front the nginx container with a corporate load balancer or WAF
   when multiple nginx replicas are required for HA; for single-host
   PoC the nginx container is the ingress.

**Verification:**

```bash
# TLS handshake + cert subject/issuer
openssl s_client -connect <host>:5443 </dev/null | openssl x509 -noout -subject -issuer

# Each public vhost through nginx
# (only the Assistant has a public vhost by default; add Release / Keycloak
#  vhost curls when their profiles are active and the matching SANs are on
#  the cert)
curl -kfsS "https://<assistant-hostname>/actuator/health/liveness"

# Logs
docker compose -f docker-compose.yaml -f test-lab/docker-compose.yaml logs -f nginx
tail -f test-lab/nginx/logs/access.log test-lab/nginx/logs/error.log
```

**Troubleshooting:**

| Symptom | Likely cause | First checks |
|---|---|---|
| nginx fails to start: `cannot load certificate` | `test-lab/nginx/certs/tls.crt` / `tls.key` missing or unreadable | `ls -l test-lab/nginx/certs/`, `openssl x509 -in test-lab/nginx/certs/tls.crt -noout -subject -issuer` |
| nginx exits with `BIO_new_file() failed` | key/cert path mismatch or perms | verify `test-lab/nginx/certs/tls.crt` matches the `server_name` and is readable by the `nginx` user (uid 101) |
| 502 Bad Gateway for a vhost | backend service not started or wrong alias | `docker compose ps`, `docker compose logs <backend>` |
| Cert subject mismatch warnings | operator served a cert without the requested SAN | reissue cert with all vhost SANs, or set the matching `*_HOSTNAME` env var to one of the cert's SANs |
| Streaming chat cuts off mid-response | `proxy_buffering on` (the default) buffers SSE; assistant vhost already sets it to `off` | confirm `test-lab/nginx/conf.d/01-assistant.conf` is present and not overridden |

## 6) Test hardening overlay

The CORE compose hardening overlay (`docker-compose.override.yaml.example`)
covers the production services. The TEST compose has a parallel overlay
(`test-lab/docker-compose.override.yaml.example`) that applies the same
hardening posture to the test services (release, postgres, keycloak,
nginx).

**Activate for the TEST compose (only when running combined labs):**

```bash
cp test-lab/docker-compose.override.yaml.example test-lab/docker-compose.override.yaml
docker compose -f docker-compose.yaml -f test-lab/docker-compose.yaml \
    -f docker-compose.override.yaml -f test-lab/docker-compose.override.yaml up -d
```

**Disable:** delete the matching `*.override.yaml` file.

**What the TEST overlay applies:**

| Setting | Default TEST compose | Hardened TEST overlay |
|---|---|---|
| `init: true` | off | on (PID 1 signal handling) |
| `stop_grace_period` | 10s (docker default) | 30s (clean DB transaction rollback) |
| `security_opt` | none | `no-new-privileges:true` |
| `cap_drop` | none | `ALL` (capabilities) |
| Container logging | unbounded `json-file` | `json-file` with `max-size:10m max-file:5` rotation |
| Host-port bindings | `0.0.0.0:PORT` | `127.0.0.1:PORT` (loopback only) |
| Postgres host port | `5432` published | not published (internal-only) |
| CPU limit | unset | per-service (small tier) |
| Memory limit | unset | per-service (small tier) |
| PID limit | unset | 128-512 per service |

**Default resource limits for the TEST services (small tier - multiply
by 4x for large):**

| Service | cpus | mem_limit | pids_limit |
|---|---:|---:|---:|
| release | 4 | 8 GB | 512 |
| postgres | 2 | 8 GB | 256 |
| keycloak | 1 | 2 GB | 128 |
| nginx | 1 | 512 MB | 64 |

For the CORE-side limits and the full network-segmentation writeup,
see [README.md §10.5](../README.md#105-hardened-deployment-overlay-production).

## 7) Common operations on the lab stack

All commands below assume `.env` (your customised copy of `.env.base`)
is present in the project root. Compose reads it implicitly - no
`--env-file` flag is needed.

### List running services

```bash
docker compose ps
```

### Tail logs

Follow logs for the Assistant (default core mode):

```bash
docker compose logs -f release-assistant
```

Follow logs for the default stack (also includes local LLM service):

```bash
docker compose logs -f llm-service-api release-assistant
```

Follow logs for the full local stack (also includes optional local
Release):

```bash
docker compose logs -f llm-service-api release-assistant release
```

### Restart services

Restart the Assistant (default core mode):

```bash
docker compose restart release-assistant
```

Restart the default stack (LLM service + Assistant):

```bash
docker compose restart llm-service-api release-assistant
```

Restart the full local stack (also includes optional local Release):

```bash
docker compose restart llm-service-api release-assistant release
```

### Pull images

```bash
docker compose pull llm-service-api release-assistant llm-service-dbinit postgres release
```

### Run LLM service DB init (one-shot)

```bash
docker compose --profile init up llm-service-dbinit
```

### Stop and remove containers

```bash
docker compose down --remove-orphans
```

### Health checks

Default stack health (Assistant + local LLM service):

```bash
curl -fsS "http://localhost:${ASSISTANT_PORT:-8090}/actuator/health/liveness" && echo " - assistant ok"
curl -fsS "http://localhost:${LLM_SERVICE_PORT:-9000}/llm/utility/ping" && echo " - llm-service ok"
```

Core services health (no local LLM service):

```bash
curl -fsS "http://localhost:${ASSISTANT_PORT:-8090}/actuator/health/liveness" && echo " - assistant ok"
```

Full local stack health (also includes optional local Release):

```bash
curl -fsS "http://localhost:${ASSISTANT_PORT:-8090}/actuator/health/liveness" && echo " - assistant ok"
curl -fsS "http://localhost:${LLM_SERVICE_PORT:-9000}/llm/utility/ping" && echo " - llm-service ok"
curl -fsS "http://localhost:${RELEASE_HTTP_PORT:-5516}/s/actuator/health/liveness" && echo " - release ok"
```

The `${VAR:-default}` shell substitution lets the curl commands run
without sourcing `.env` first; values default to the published ports
when not exported.

## 8) Lab setup recipes

Each recipe is a complete copy/paste workflow: hosts file, env file,
cert generation (if applicable), `docker compose` invocations for run
/ check / destroy. Use these as starting points; customize the `.env`
for your environment.

### Common invocation pattern

```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml \
  [-f test-lab/docker-compose.yaml] \
  [-f docker-compose.with-internal-ca.yaml] \
  --profile <profiles> \
  <command>
```

Compose reads `.env` from the project root implicitly, so no
`--env-file` flag is needed. The `.env` file is gitignored; copy it
from `.env.base` and edit per host.

If you only want to run the test stack (e.g. against an existing
external Release / postgres), drop `-f docker-compose.yaml`. If you
only want the core stack (e.g. for production-like deploys against
external IdP, DB, Release), drop `-f test-lab/docker-compose.yaml`.

Add `-f docker-compose.with-internal-ca.yaml` only when you need
internal corporate CA trust (IdP / Release / LLM endpoints whose
certs are signed by a private chain). Requires `certs/cacerts.jks` and
`certs/ca-bundle.pem` at the repo root - generate with
`./install-internal-ca.sh <corp-ca-bundle.pem>` (see
[README.md §28](../README.md#28-private-ca--self-signed-trust)).
Without this overlay, the three CORE services use the system default
trust stores.

### 8.1 http, with-postgres, with-release, digital.ai idp

`/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts` on Windows):
```
127.0.0.1       release.example.digital.ai.local
127.0.0.1       release-assistant.example.digital.ai.local
```

`.env` (customised from `.env.base`):
```bash
RELEASE_ASSISTANT_IMAGE=xebialabsunsupported/dai-release-assistant:0.2.0
LLM_SERVICE_API_IMAGE=docker.usw2mgt.dev.digitalai.cloud/digital-ai/k6i-llm-service/llm-service-api:0.0.1.255
LLM_SERVICE_DBINIT_IMAGE=docker.usw2mgt.dev.digitalai.cloud/digital-ai/k6i-llm-service/llm-service-dbinit:0.0.1.255
RELEASE_IMAGE=xebialabsunsupported/xl-release:26.3.0-beta.708
KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.6
POSTGRES_IMAGE=postgres:18.4-alpine
NGINX_IMAGE=nginx:1.31-alpine

ASSISTANT_PORT=8090
LLM_SERVICE_PORT=9000
RELEASE_HTTP_PORT=5516
KEYCLOAK_HTTP_PORT=25080
KEYCLOAK_MGMT_PORT=25090
POSTGRES_PORT=5432

POSTGRES_HOSTNAME=postgres
ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.local
RELEASE_HOSTNAME=release.example.digital.ai.local
IDP_HOSTNAME=replace-me

RELEASE_PUBLIC_URL=http://${RELEASE_HOSTNAME}:${RELEASE_HTTP_PORT}
RELEASE_ASSISTANT_PUBLIC_URL=http://${ASSISTANT_HOSTNAME}:${ASSISTANT_PORT}

OAUTH2_TOKEN_CLIENT_ID=replace-me
OAUTH2_TOKEN_CLIENT_SECRET=replace-me
OAUTH2_SCOPES="openid, dai-svc"
OIDC_ISSUER_URI=https://${IDP_HOSTNAME}/auth/realms/onboarding
```

Run:
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-release \
  up -d postgres release release-assistant
```

If your IdP / Release / Assistant are signed by an internal CA, also
add `-f docker-compose.with-internal-ca.yaml` to every `docker compose`
command in this recipe (and run
`./install-internal-ca.sh <corp-ca-bundle.pem>` first to populate
`certs/`).

Check:
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-release \
  ps
```

Open `http://release.example.digital.ai.local:5516/`

Destroy:
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-release \
  down --remove-orphans
```

### 8.2 https, with-postgres, with-release, digital.ai idp

`/etc/hosts`:
```
127.0.0.1       release.example.digital.ai.nginx
127.0.0.1       release-assistant.example.digital.ai.nginx
```

`.env`:
```bash
RELEASE_ASSISTANT_IMAGE=xebialabsunsupported/dai-release-assistant:0.2.0
LLM_SERVICE_API_IMAGE=docker.usw2mgt.dev.digitalai.cloud/digital-ai/k6i-llm-service/llm-service-api:0.0.1.255
LLM_SERVICE_DBINIT_IMAGE=docker.usw2mgt.dev.digitalai.cloud/digital-ai/k6i-llm-service/llm-service-dbinit:0.0.1.255
RELEASE_IMAGE=xebialabsunsupported/xl-release:26.3.0-beta.708
KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.6
POSTGRES_IMAGE=postgres:18.4-alpine
NGINX_IMAGE=nginx:1.31-alpine

ASSISTANT_PORT=8090
LLM_SERVICE_PORT=9000
RELEASE_HTTP_PORT=5516
KEYCLOAK_HTTP_PORT=25080
KEYCLOAK_MGMT_PORT=25090
POSTGRES_PORT=5432
NGINX_HTTPS_PORT=5443

POSTGRES_HOSTNAME=postgres
ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.local
RELEASE_HOSTNAME=release.example.digital.ai.local
IDP_HOSTNAME=replace-me

NGINX_RELEASE_HOSTNAME=release.example.digital.ai.nginx
NGINX_ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.nginx

RELEASE_PUBLIC_URL=https://${NGINX_RELEASE_HOSTNAME}:${NGINX_HTTPS_PORT}
RELEASE_ASSISTANT_PUBLIC_URL=https://${NGINX_ASSISTANT_HOSTNAME}:${NGINX_HTTPS_PORT}

OAUTH2_TOKEN_CLIENT_ID=replace-me
OAUTH2_TOKEN_CLIENT_SECRET=replace-me
OAUTH2_SCOPES="openid, dai-svc"
OIDC_ISSUER_URI=https://${IDP_HOSTNAME}/auth/realms/onboarding
```

Self-signed certs for local labs only:
```bash
SAN="DNS:release.example.digital.ai.nginx,DNS:release-assistant.example.digital.ai.nginx,DNS:identity.example.digital.ai.nginx"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout test-lab/nginx/certs/tls.key -out test-lab/nginx/certs/tls.crt \
    -subj "/CN=ask-release" \
    -addext "subjectAltName=${SAN}"
```

Run:
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-nginx --profile with-release \
  up -d postgres nginx release release-assistant
```

If your IdP / Release / Assistant are signed by an internal CA, also
add `-f docker-compose.with-internal-ca.yaml` to every `docker compose`
command in this recipe (and run
`./install-internal-ca.sh <corp-ca-bundle.pem>` first to populate
`certs/`).

Check:
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-nginx --profile with-release \
  ps
```

Open `https://release.example.digital.ai.nginx:5443/`

First login suggestion: use `gandalf/gandalf` (admin-like) or
`alice/alice` (developer-role testing), see §2.1.

Destroy:
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-nginx --profile with-release \
  down --remove-orphans
```

### 8.3 https, with-llm, with-postgres, with-release, digital.ai idp

`/etc/hosts`:
```
127.0.0.1       release.example.digital.ai.nginx
127.0.0.1       release-assistant.example.digital.ai.nginx
```

`.env`:
```bash
RELEASE_ASSISTANT_IMAGE=xebialabsunsupported/dai-release-assistant:0.2.0
LLM_SERVICE_API_IMAGE=docker.usw2mgt.dev.digitalai.cloud/digital-ai/k6i-llm-service/llm-service-api:0.0.1.255
LLM_SERVICE_DBINIT_IMAGE=docker.usw2mgt.dev.digitalai.cloud/digital-ai/k6i-llm-service/llm-service-dbinit:0.0.1.255
RELEASE_IMAGE=xebialabsunsupported/xl-release:26.3.0-beta.708
KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.6
POSTGRES_IMAGE=postgres:18.4-alpine
NGINX_IMAGE=nginx:1.31-alpine

ASSISTANT_PORT=8090
LLM_SERVICE_PORT=9000
RELEASE_HTTP_PORT=5516
KEYCLOAK_HTTP_PORT=25080
KEYCLOAK_MGMT_PORT=25090
POSTGRES_PORT=5432
NGINX_HTTPS_PORT=5443

POSTGRES_HOSTNAME=postgres
ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.local
RELEASE_HOSTNAME=release.example.digital.ai.local
IDP_HOSTNAME=identity.staging.digital.ai

NGINX_RELEASE_HOSTNAME=release.example.digital.ai.nginx
NGINX_ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.nginx

RELEASE_PUBLIC_URL=https://${NGINX_RELEASE_HOSTNAME}:${NGINX_HTTPS_PORT}
RELEASE_ASSISTANT_PUBLIC_URL=https://${NGINX_ASSISTANT_HOSTNAME}:${NGINX_HTTPS_PORT}

OAUTH2_TOKEN_CLIENT_ID=replace-me
OAUTH2_TOKEN_CLIENT_SECRET=replace-me
OAUTH2_SCOPES="openid, dai-svc"
OIDC_ISSUER_URI=https://${IDP_HOSTNAME}/auth/realms/onboarding

AI_LLM_BASE_URL=http://llm-service-api:${LLM_SERVICE_PORT}/llm
AI_LLM_CHAT_MODEL=replace-me

DAI_ACCOUNT_ID=replace-me
DAI_AUTH_ISSUER_PATTERN=${OIDC_ISSUER_URI}
LLM_SERVICE_DEFAULT_PROVIDER_CONFIG=e...
```

Self-signed certs:
```bash
SAN="DNS:release.example.digital.ai.nginx,DNS:release-assistant.example.digital.ai.nginx,DNS:identity.example.digital.ai.nginx"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout test-lab/nginx/certs/tls.key -out test-lab/nginx/certs/tls.crt \
    -subj "/CN=ask-release" \
    -addext "subjectAltName=${SAN}"
```

Run (note `--profile with-llm-service` to also start the local LLM service):
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-nginx --profile with-release \
  up -d postgres llm-service-api nginx release release-assistant
```

If your IdP / Release / Assistant / LLM backend are signed by an
internal CA, also add `-f docker-compose.with-internal-ca.yaml` to
every `docker compose` command in this recipe (and run
`./install-internal-ca.sh <corp-ca-bundle.pem>` first to populate
`certs/`).

Check:
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-nginx --profile with-release \
  ps
```

Open `https://release.example.digital.ai.nginx:5443/`

Destroy:
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml -f test-lab/docker-compose.yaml \
  --profile with-postgres --profile with-llm-service --profile with-nginx --profile with-release \
  down --remove-orphans
```

### 8.4 https, with-llm, with-postgres, with-release, with-keycloak

`/etc/hosts`:
```
127.0.0.1       release.example.digital.ai.nginx
127.0.0.1       release-assistant.example.digital.ai.nginx
127.0.0.1       identity.example.digital.ai.nginx
```

`.env`:
```bash
RELEASE_ASSISTANT_IMAGE=xebialabsunsupported/dai-release-assistant:0.2.0
LLM_SERVICE_API_IMAGE=docker.usw2mgt.dev.digitalai.cloud/digital-ai/k6i-llm-service/llm-service-api:0.0.1.255
LLM_SERVICE_DBINIT_IMAGE=docker.usw2mgt.dev.digitalai.cloud/digital-ai/k6i-llm-service/llm-service-dbinit:0.0.1.255
RELEASE_IMAGE=xebialabsunsupported/xl-release:26.3.0-beta.708
KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.6
POSTGRES_IMAGE=postgres:18.4-alpine
NGINX_IMAGE=nginx:1.31-alpine

ASSISTANT_PORT=8090
LLM_SERVICE_PORT=9000
RELEASE_HTTP_PORT=5516
KEYCLOAK_HTTP_PORT=25080
KEYCLOAK_MGMT_PORT=25090
POSTGRES_PORT=5432
NGINX_HTTPS_PORT=5443

POSTGRES_HOSTNAME=postgres
ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.local
RELEASE_HOSTNAME=release.example.digital.ai.local
IDP_HOSTNAME=identity.example.digital.ai.local

NGINX_RELEASE_HOSTNAME=release.example.digital.ai.nginx
NGINX_ASSISTANT_HOSTNAME=release-assistant.example.digital.ai.nginx
NGINX_IDP_HOSTNAME=identity.example.digital.ai.nginx

RELEASE_PUBLIC_URL=https://${NGINX_RELEASE_HOSTNAME}:${NGINX_HTTPS_PORT}
RELEASE_ASSISTANT_PUBLIC_URL=https://${NGINX_ASSISTANT_HOSTNAME}:${NGINX_HTTPS_PORT}

OAUTH2_SCOPES="openid"
OAUTH2_TOKEN_CLIENT_ID=xl-release
OAUTH2_TOKEN_CLIENT_SECRET=ab2088f6-2251-4233-9b22-e24db6a67483
KEYCLOAK_PROTOCOL=https
KEYCLOAK_HOSTNAME=${NGINX_IDP_HOSTNAME}
KEYCLOAK_PORT=${NGINX_HTTPS_PORT}
KEYCLOAK_REALM=xl-platform
KEYCLOAK_LOCAL_ISSUER=${KEYCLOAK_PROTOCOL}://${NGINX_IDP_HOSTNAME}:${NGINX_HTTPS_PORT}/realms/${KEYCLOAK_REALM}
OIDC_ISSUER_URI=${KEYCLOAK_LOCAL_ISSUER}

AI_LLM_BASE_URL=http://llm-service-api:${LLM_SERVICE_PORT}/llm
AI_LLM_CHAT_MODEL=replace-me

DAI_ACCOUNT_ID=replace-me
DAI_AUTH_ISSUER_PATTERN=${OIDC_ISSUER_URI}
LLM_SERVICE_DEFAULT_PROVIDER_CONFIG=e...
```

Self-signed certs:
```bash
SAN="DNS:release.example.digital.ai.nginx,DNS:release-assistant.example.digital.ai.nginx,DNS:identity.example.digital.ai.nginx"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout test-lab/nginx/certs/tls.key -out test-lab/nginx/certs/tls.crt \
    -subj "/CN=ask-release" \
    -addext "subjectAltName=${SAN}"
```

Build JKS and PEM truststore from the nginx self-signed cert (writes
to `./certs/`, consumed by `-f docker-compose.with-internal-ca.yaml`
and `-f test-lab/docker-compose.with-internal-ca.yaml`):
```bash
./install-internal-ca.sh test-lab/nginx/certs/tls.crt
```

Run:
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

Check:
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

Open `https://release.example.digital.ai.nginx:5443/`

Destroy:
```bash
docker compose \
  --project-directory . \
  -f docker-compose.yaml \
  -f docker-compose.with-internal-ca.yaml \
  -f test-lab/docker-compose.yaml \
  -f test-lab/docker-compose.with-internal-ca.yaml \
  --profile with-postgres --profile with-llm-service --profile with-keycloak --profile with-nginx --profile with-release \
  down --remove-orphans
```

### 8.5 https, with-llm, with-release, with-keycloak (no in-stack Postgres)

Same as recipe 8.4 but drop `--profile with-postgres` and set
`POSTGRES_HOSTNAME=<your-managed-postgres-host>` in `.env` when you
want to use a customer-managed PostgreSQL.

First login suggestion: use `gandalf/gandalf` or `alice/alice` (see §2.1).

### 8.6 https, with-llm, with-postgres, with-keycloak (no in-stack Release)

Same as recipe 8.4 but drop `--profile with-release` (and the
`release` service from the `up -d` list) when you want to point the
Assistant at an existing external Digital.ai Release installation.
The Assistant reaches the embedded MCP endpoint on the external
Release via the `${RELEASE_PUBLIC_URL}${RELEASE_MCP_SERVER_ENDPOINT:-/s/mcp}`
URL chain.

First login suggestion when local Keycloak is in use: `gandalf/gandalf`
or `alice/alice` (see §2.1).

### Notes

- All commands should be run from the repository root.
- `--project-directory .` is required when combining the two compose
  files so Compose resolves `extends` paths against the project root.
- `test-lab/` is gitignored in spirit - keep certs, logs, and the named
  `ask-release-postgres-data` volume outside source control.
- See the [README.md](../README.md) for the full deployment, sizing,
  security, and troubleshooting reference.

## 9) Hybrid scenario (On-Prem Assistant + SaaS LLM)

Use this scenario when the Assistant runs on-prem, while model
inference is handled by Digital.ai SaaS LLM endpoints. The embedded
MCP endpoint on the (external or in-stack) Release is still the bridge
between the Assistant and Digital.ai Release data/actions.

Scope in this repository:

- Start `release-assistant` only.
- Do not start local `llm-service-dbinit` or `llm-service-api`.

Required minimum configuration:

- `RELEASE_PUBLIC_URL`
- `RELEASE_MCP_SERVER_ENDPOINT`
- `OAUTH2_TOKEN_CLIENT_ID`, `OAUTH2_TOKEN_CLIENT_SECRET`
- `OIDC_ISSUER_URI`
- `DB_URL_SUFFIX`, `DB_USERNAME`, `DB_PASSWORD`

Installation steps:

1. Prepare `.env` with the required values above.
2. Configure Assistant runtime to use your approved SaaS LLM endpoint
   for your environment.
3. Start core services without local LLM:

```bash
docker compose up -d release-assistant
```

4. Verify deployment:

```bash
curl -fsS "http://localhost:${ASSISTANT_PORT:-8090}/actuator/health/liveness" && echo " - assistant ok"
```

5. Run an end-to-end Ask Release chat test from Release UI.

Security checks for this scenario:

- Allow egress from Assistant to the approved SaaS LLM endpoint only.
- Keep provider credentials out of local compose configuration in this
  mode.

## 10) BYO-LLM scenario (LLM Service Self-Hosted)

Use this scenario when the customer controls model provider selection
and provider credentials, with local LLM Service running in the
customer environment.

Scope in this repository:

- Start `llm-service-dbinit` + `llm-service-api` + `release-assistant`.
- Optionally include local postgres profile for labs.

Required minimum configuration:

- `RELEASE_PUBLIC_URL`
- `RELEASE_MCP_SERVER_ENDPOINT`
- `OAUTH2_TOKEN_CLIENT_ID`, `OAUTH2_TOKEN_CLIENT_SECRET`
- `OIDC_ISSUER_URI`
- `DB_URL_SUFFIX`, `DB_USERNAME`, `DB_PASSWORD`
- `LLM_DB_HOST`, `LLM_DB_NAME`, `LLM_DB_USERNAME`, `LLM_DB_PASSWORD`
- `LLM_SERVICE_DEFAULT_PROVIDER_NAME`
- `LLM_SERVICE_DEFAULT_PROVIDER_CONFIG` (base64)
- `LLM_SERVICE_DEFAULT_SYSTEM_MODEL_ALIAS_MAPPINGS` (optional, base64)

Installation steps:

1. Prepare `.env` with the required values above.
2. Start BYO-LLM runtime stack:

```bash
docker compose --profile with-llm-service up llm-service-dbinit
docker compose --profile with-llm-service up -d llm-service-api release-assistant
```

3. If using local postgres profile in labs:

```bash
docker compose --profile with-postgres up -d postgres
docker compose --profile with-postgres --profile with-llm-service up llm-service-dbinit
docker compose --profile with-postgres --profile with-llm-service up -d llm-service-api release-assistant
```

4. Verify deployment:

```bash
curl -fsS "http://localhost:${ASSISTANT_PORT:-8090}/actuator/health/liveness" && echo " - assistant ok"
curl -fsS "http://localhost:${LLM_SERVICE_PORT:-9000}/llm/utility/ping" && echo " - llm-service ok"
```

5. Run end-to-end Ask Release chat test and one RBAC negative test.

Security checks for this scenario:

- Store provider credentials via secret manager and inject at runtime.
- Restrict LLM service egress to approved provider endpoints.

## 11) Lab architecture notes

Lab-derived constraints and recommendations that apply across
deployment modes:

- **Container-native delivery only:** Ask Release components are
  supported as containers.
- **On-Premises LLM Service Gateway model not supported:** The
  "On-Premises LLM Service Gateway" model described in the Labs
  architecture source is currently not supported in this deployment
  guide due to security constraints.
- **PostgreSQL consolidation is supported:** Customers can host
  Assistant and LLM service data on the same PostgreSQL server using
  separate databases/schemas.

## 12) Test-stack configuration reference

These vars are not declared in `.env.base`; their `${VAR:-default}`
fallbacks live in the per-service test compose file
(`test-lab/*/compose.yaml`). Override per deployment in `.env`.

### Test-stack image tags

| Variable | Default | Description |
|---|---|---|
| `RELEASE_IMAGE` | `xebialabsunsupported/xl-release:26.3.0-beta.708` | Local Release image (used by `--profile with-release`) |
| `KEYCLOAK_IMAGE` | `quay.io/keycloak/keycloak:26.6` | Local Keycloak image (used by `--profile with-keycloak`) |
| `POSTGRES_IMAGE` | `postgres:18.4-alpine` | Postgres image (used by `--profile with-postgres` / `with-release`) |
| `NGINX_IMAGE` | `nginx:1.31-alpine` | nginx image (used by `--profile with-nginx`) |

> **Production image replacement**: the `xebialabsunsupported/*`
> references above are internal-only. For production documentation and
> production deployments, switch to the approved `xebialabs/*` image
> references.

### Test-stack exposed host ports

| Variable | Default | Service | Description |
|---|---:|---|---|
| `RELEASE_HTTP_PORT` | `5516` | release | Host port the local Release publishes |
| `KEYCLOAK_HTTP_PORT` | `25080` | keycloak | Host port for Keycloak HTTP listener |
| `KEYCLOAK_MGMT_PORT` | `25090` | keycloak | Host port for Keycloak management/health |
| `POSTGRES_PORT` | `5432` | postgres | Host port for Postgres (drop the publish in the hardened overlay; postgres becomes internal-only) |
| `NGINX_HTTPS_PORT` | `5443` | nginx | Host port the nginx proxy publishes for HTTPS |

### Test-stack public FQDNs

These are consumed by the nginx vhost configs and injected into TLS
cert SANs. Leave the defaults for local labs; override to the real
public FQDNs in `.env` for production.

| Variable | Default | Description |
|---|---|---|
| `RELEASE_HOSTNAME` | `release.example.digital.ai.local` | Public FQDN of the Release (used by nginx vhost + TLS cert SAN + Docker network alias) |
| `IDP_HOSTNAME` | `identity.example.digital.ai.local` | Public FQDN of the IdP (used by nginx vhost + TLS cert SAN + Docker network alias + Keycloak `KC_HOSTNAME`) |

### Compose-internal defaults (`test-lab/keycloak/compose.yaml`)

| Variable | Compose default | Description |
|---|---|---|
| `KEYCLOAK_ADMIN_USER` | `admin` | Bootstrap admin username (`KC_BOOTSTRAP_ADMIN_USERNAME`) |
| `KEYCLOAK_ADMIN_PASSWORD` | `admin` | Bootstrap admin password (`KC_BOOTSTRAP_ADMIN_PASSWORD`) |

The realm is preloaded from `test-lab/keycloak/data/xl-platform-realm.json`
and the `KC_HOSTNAME` image env is wired to `${IDP_HOSTNAME}`.
`KEYCLOAK_REALM` and `KEYCLOAK_LOCAL_ISSUER` (commented template in
`.env.base`) are not consumed by the local Keycloak container directly -
they exist to give the other services a single derived issuer URI
(`http://${IDP_HOSTNAME}:${KEYCLOAK_HTTP_PORT}/realms/${KEYCLOAK_REALM}`)
to point `OIDC_ISSUER_URI` and `DAI_AUTH_ISSUER_PATTERN` at when the
`with-keycloak` profile is active.

### Compose-internal defaults (`test-lab/nginx/compose.yaml`)

| Variable | Compose default | Description |
|---|---|---|
| `NGINX_HOSTNAME` | `nginx.example.digital.ai.local` | Internal Docker network alias for the nginx container |
| `NGINX_ASSISTANT_HOSTNAME` | _(empty)_ | Optional extra network alias for nginx so it is reachable by the Assistant public FQDN |
| `NGINX_RELEASE_HOSTNAME` | _(empty)_ | Optional extra network alias for nginx so it is reachable by the Release public FQDN (only with `--profile with-release`) |
| `NGINX_IDP_HOSTNAME` | _(empty)_ | Optional extra network alias for nginx so it is reachable by the IdP public FQDN (only with `--profile with-keycloak`) |

The vhost configs (`test-lab/nginx/conf.d/*.conf`) reference the
`ASSISTANT_HOSTNAME`, `RELEASE_HOSTNAME`, and `IDP_HOSTNAME` vars from
`.env.base` directly. The `NGINX_*_HOSTNAME` vars above only need to be
set when you want nginx to also be reachable by an alternate FQDN that
is not on the TLS cert (e.g. for split-DNS behind a corporate LB).

### Compose-internal defaults (`test-lab/postgres/compose.yaml`)

| Variable | Compose default | Description |
|---|---|---|
| `POSTGRES_ADMIN_USER` | `postgres` | Superuser name created on first startup (`POSTGRES_USER`) |
| `POSTGRES_ADMIN_PASSWORD` | `postgres` | Superuser password created on first startup (`POSTGRES_PASSWORD`) |

### Compose-internal defaults (`test-lab/release/compose.yaml`)

#### Release image / admin

| Variable | Compose default | Description |
|---|---|---|
| `RELEASE_ADMIN_PASSWORD` | `admin` | Initial admin password set on first startup (`ADMIN_PASSWORD`) |

#### Release database (env-driven, consumed at container start)

| Variable | Compose default | Description |
|---|---|---|
| `XL_DB_URL` | `jdbc:postgresql://${POSTGRES_HOSTNAME}:${POSTGRES_PORT}/xlrelease?ssl=false` | Release main DB JDBC URL |
| `XL_DB_USERNAME` | `xlrelease` | Release main DB user |
| `XL_DB_PASSWORD` | `xlrelease` | Release main DB password |
| `XL_REPORT_DB_URL` | `jdbc:postgresql://${POSTGRES_HOSTNAME}:${POSTGRES_PORT}/xlarchive?ssl=false` | Release reporting DB JDBC URL |
| `XL_REPORT_DB_USERNAME` | `xlarchive` | Release reporting DB user |
| `XL_REPORT_DB_PASSWORD` | `xlarchive` | Release reporting DB password |

#### Release OIDC (env-driven, consumed at container start)

| Variable | Compose default | Description |
|---|---|---|
| `RELEASE_OIDC_CLIENT_ID` | `${OAUTH2_TOKEN_CLIENT_ID}` | OIDC client ID used by Release |
| `RELEASE_OIDC_CLIENT_SECRET` | `${OAUTH2_TOKEN_CLIENT_SECRET}` | OIDC client secret used by Release |
| `RELEASE_OIDC_ISSUER` | `${OIDC_ISSUER_URI}` | OIDC issuer used by Release |
| `RELEASE_OIDC_KEY_RETRIEVAL_URI` | `${OIDC_ISSUER_URI}/protocol/openid-connect/certs` | JWKS URL used by Release |
| `RELEASE_OIDC_ACCESS_TOKEN_URI` | `${OIDC_ISSUER_URI}/protocol/openid-connect/token` | Token endpoint used by Release |
| `RELEASE_OIDC_USER_AUTHORIZATION_URI` | `${OIDC_ISSUER_URI}/protocol/openid-connect/auth` | Authorization endpoint used by Release |
| `RELEASE_OIDC_LOGOUT_URI` | `${OIDC_ISSUER_URI}/protocol/openid-connect/logout` | Logout endpoint used by Release |
| `RELEASE_OIDC_REDIRECT_URI` | `${RELEASE_PUBLIC_URL}/oidc-login` | OIDC redirect URI used by Release (login + post-logout by default) |
| `RELEASE_OIDC_POST_LOGOUT_REDIRECT_URI` | `${RELEASE_PUBLIC_URL}/oidc-login` | OIDC post-logout redirect URI used by Release |

#### Release HOCON template vars (`test-lab/release/default-conf/xl-release.conf.template`)

These are resolved by HOCON `${?VAR}` substitution inside
`xl-release.conf.template` at Release startup (no init container
required). They are NOT exposed as container env vars; pass them
through the Release container environment from `.env`.

| Variable | Description |
|---|---|
| `XL_CLUSTER_MODE` | Cluster mode (`default`, `hot-standby`, `full`) |
| `XLR_CLUSTER_NAME` | Cluster name |
| `XLR_CLUSTER_MANAGER` | Cluster manager host |
| `XLR_HTTP2_ENABLED` | HTTP/2 toggle (`true` / `false`) |
| `XL_LICENSE_KIND` | License kind |
| `XL_DB_DRIVER` | DB driver classname (`xl.database.db-driver-classname`) |
| `XL_DB_MAX_POOL_SIZE` | Main DB pool size (`xl.database.max-pool-size`) |
| `XL_REPORT_DB_MAX_POOL_SIZE` | Reporting DB pool size (`xl.reporting.max-pool-size`) |
| `XL_METRICS_ENABLED` | Metrics endpoint toggle (`xl.metrics.enabled`) |
| `ENABLE_EMBEDDED_QUEUE` | Embedded task queue toggle (`xl.queue.embedded`) |
| `XLR_TASK_QUEUE_TYPE` | Task queue type |
| `XLR_TASK_QUEUE_CONNECTOR_TYPE` | Task queue connector type |
| `XLR_TASK_QUEUE_URL` | Task queue URL |
| `XLR_TASK_QUEUE_NAME` | Task queue name |
| `XLR_TASK_QUEUE_USERNAME` | Task queue username |
| `XLR_TASK_QUEUE_PASSWORD` | Task queue password |

## 13) Lab troubleshooting

Common issues that only appear when one or more lab profiles are
active.

| Symptom | Likely cause | First checks |
|---|---|---|
| nginx fails to start (`cannot load certificate`) | `test-lab/nginx/certs/tls.crt` / `tls.key` missing or unreadable | `ls -l test-lab/nginx/certs/`, `openssl x509 -in test-lab/nginx/certs/tls.crt -noout -subject -issuer` |
| nginx 502 for a vhost | backend not started under the active profile set, or wrong alias | `docker compose ps`, `docker compose logs <backend>`, confirm the vhost's profile is active |
| TLS handshake fails for a public FQDN | cert SAN does not include the requested hostname | reissue cert with the FQDN as a SAN, or set the matching `*_HOSTNAME` env var to a SAN you already have |
| `network ask-release-data declared as external, but could not be found` (or `ask-release-net`) | TEST compose is being used standalone and the shared networks are flagged `external: true` | `git pull` - the fix drops `external: true` from the networks in `test-lab/docker-compose.yaml` so Compose auto-creates them; standalone runs work without first running the CORE compose |
| `Error response from daemon: error while creating mount source path '.../test-lab/nginx/certs/cacerts.jks': chown ...: permission denied` | Stale directory at `test-lab/nginx/certs/cacerts.jks` from a prior failed run; `test-lab/release/compose.yaml` previously pointed at this path | `rmdir test-lab/nginx/certs/cacerts.jks` (current compose now sources `certs/cacerts.jks` from the repo root, populated by `install-internal-ca.sh`); rerun `./install-internal-ca.sh <corp-ca-bundle.pem>` if `certs/cacerts.jks` is also missing |

For the CORE-side troubleshooting (Assistant / LLM service auth,
DB connectivity, OIDC issuer mismatches), see
[README.md §14.3](../README.md#143-common-issues-and-first-response).

## 14) Notes

- The `test-lab/` directory is intentionally lab-grade. It uses a
  permissive Keycloak realm, in-memory H2 by default, and
  in-container bind mounts for certs and logs. Do not use the lab
  stack as-is in production.
- Every lab profile is opt-in; the CORE compose starts the
  release-assistant and (with `--profile with-llm-service`)
  llm-service-api without needing any of `test-lab/`.
- The MCP (Model Context Protocol) server is no longer a separate
  service in this compose stack. It is embedded inside Digital.ai
  Release and exposed at
  `${RELEASE_PUBLIC_URL}${RELEASE_MCP_SERVER_ENDPOINT:-/s/mcp}`.
  The Assistant connects to that endpoint directly over the
  `ask-release-net` bridge; there is no MCP container, port, image,
  or OIDC block.
- The two compose files use shared network and volume names so the
  combined CORE + TEST stack resolves to a single set of resources.
  Standalone runs of either compose also work because Compose
  auto-creates the shared networks and volumes when they are not
  declared `external: true`.
- See [README.md](../README.md) for production deployment patterns
  (external Postgres / Release / IdP, sizing, secure connectivity,
  backup/DR, monitoring, private-CA trust).
