# Ask Release Docs Agent

Use this agent guide to choose the right documentation source for setup and operations.

## File map

### 1) `README.md` (root)
- Primary reference for the CORE/production deployment model.
- Covers architecture, network flows, security/RBAC, prerequisites, sizing, and install scenarios.
- Use this first when deploying with external/customer-managed Release, Postgres, and OIDC.

### 2) `test-lab/QUICK-START.md`
- Fast path for a full local HTTP lab.
- Focuses on step-by-step commands and run order for:
  - `with-postgres`
  - `with-llm-service`
  - `with-release`
  - `with-keycloak`
- Includes local hostnames, minimum `.env` values, health checks, log commands, and teardown.

### 3) `agents/skills/ask-release-quick-start/SKILL.md`
- Operational skill instructions for executing the Quick Start workflow.
- Defines required user inputs, expected `.env` overrides, startup sequence, verification, and teardown.
- Use when assisting a user interactively through local-lab setup and validation.

### 4) `agents/skills/ask-release-https-full-lab/SKILL.md`
- Operational skill instructions for recipe `8.4` in `test-lab/README.md`.
- Covers HTTPS + nginx + internal-CA overlays with:
  - `with-postgres`
  - `with-llm-service`
  - `with-release`
  - `with-keycloak`
- Includes `/etc/hosts`, cert generation, truststore generation, compose run order, verification, and teardown.

## Selection rules

- If the user asks for production/on-prem guidance, start with `README.md`.
- If the user asks for fastest local setup, start with `test-lab/QUICK-START.md`.
- If the task is to run the setup as an assistant workflow, follow `agents/skills/ask-release-quick-start/SKILL.md`.
- If the task is HTTPS full-lab setup (recipe `8.4`), follow `agents/skills/ask-release-https-full-lab/SKILL.md`.

## Recommended execution order for local lab support

1. Apply behavior and guardrails from `agents/skills/ask-release-quick-start/SKILL.md`.
2. Read `test-lab/QUICK-START.md` for current command flow.
3. Use `README.md` only for deeper context, production contrasts, or troubleshooting beyond quick-start scope.
