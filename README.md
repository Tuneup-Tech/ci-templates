# ci-templates

Shared GitHub Actions reusable workflows for all Tuneup Tech projects.

## Workflows

### `docker-build-push-deploy.yml`
For any project that has a **Dockerfile** and deploys via Docker Compose.

**Flow:** `checkout → build image → push to GHCR → SSH → compose pull → compose up`

| Input | Required | Default | Description |
|---|---|---|---|
| `image_name` | ✅ | — | GHCR image name, e.g. `true-cost-be` |
| `dockerfile_path` | ❌ | `Dockerfile` | Path to Dockerfile relative to repo root |
| `build_context` | ❌ | `.` | Docker build context |
| `compose_file` | ❌ | `docker-compose.yml` | Compose file to copy to server |
| `compose_service` | ✅ | — | Docker Compose service name |
| `server_path` | ✅ | — | Absolute path on server, e.g. `/srv/true-cost-be` |
| `ssh_port` | ❌ | `22` | SSH port |
| `post_deploy_script` | ❌ | `""` | Shell commands to run after container starts |
| `has_env` | ❌ | `false` | Write the `APP_ENV` secret (base64) as `.env` on the server and `.env.production` for the build |
| `env_sample` | ❌ | `""` | Repo path listing required `APP_ENV` keys (e.g. `.env.example`). Checked on the runner before the build; a missing, blank or `<placeholder>` key stops the deploy. Lines ending `# optional` are skipped. |
| `liveness_seconds` | ❌ | `60` | After post-deploy, watch the service this long; fail the run if any container stopped, restarted or went unhealthy (prints its last 40 log lines). `0` skips. |
| secrets `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | ❌ | — | Org secrets (passed by `secrets: inherit`). When set, a final `notify` job sends one Telegram message per deploy: ✅/❌/⚪, the PRs shipped since the last successful deploy, the failed step + its error line, and the run link. Unset = no message; the job never fails the run. |

> `docker compose up -d` returns as soon as a container *starts*. On 2026-10-27 true-cost crash-looped for 7.5h on a missing env var while the run showed green — `liveness_seconds` and `env_sample` close that gap.

---

### `frontend-build-deploy.yml`
For **static frontends** (React/Vite/etc.) — builds locally, uploads `dist/` to server via SCP.

**Flow:** `checkout → yarn install → yarn build → upload artifact → SCP to server`

| Input | Required | Default | Description |
|---|---|---|---|
| `node_version` | ❌ | `22` | Node.js version |
| `package_manager` | ❌ | `yarn` | `yarn` or `npm` |
| `build_command` | ❌ | `yarn build` | Build command |
| `dist_path` | ❌ | `dist` | Output directory |
| `server_path` | ✅ | — | Absolute path on server |
| `ssh_port` | ❌ | `22` | SSH port |
| `post_deploy_script` | ❌ | `""` | Shell commands after upload |

---

### `infra-compose-deploy.yml`
For **infrastructure-only** repos (traefik, uptime-kuma, etc.) — no build step, just copies config files and runs `compose up`.

**Flow:** `checkout → SCP compose + extra files → SSH → compose pull → compose up`

| Input | Required | Default | Description |
|---|---|---|---|
| `server_path` | ✅ | — | Absolute path on server |
| `compose_file` | ❌ | `docker-compose.yml` | Compose file path |
| `extra_files` | ❌ | `""` | Comma-separated extra files to copy |
| `services` | ❌ | `""` | Space-separated services (empty = all) |
| `ssh_port` | ❌ | `22` | SSH port |
| `has_env` | ❌ | `false` | Write the `APP_ENV` secret (base64) as `.env` on the server |
| `env_sample` | ❌ | `""` | Repo path listing required `APP_ENV` keys (e.g. `.env-sample`). Checked on the runner before anything touches the server; a missing, blank or `<placeholder>` key stops the deploy. Lines ending `# optional` are skipped. |
| `liveness_seconds` | ❌ | `60` | After deploy, watch the stack this long; fail the run if any container stopped, restarted or went unhealthy (prints its last 40 log lines). A one-shot container (restart policy `no`) that exited `0` is fine; a long-running one that exited `0` still fails. `0` skips. |
| secrets `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | ❌ | — | Same per-deploy Telegram message as `docker-build-push-deploy`. Callers that list secrets one by one (not `secrets: inherit`) must pass these two as well. Unset = no message. |

> `docker compose up -d` returns as soon as containers *start*. `liveness_seconds` catches a stack that crash-loops after a green deploy. It is the shared `.github/actions/verify-stayed-up` action, also used by `docker-build-push-deploy`.

> `APP_ENV` replaces the **whole** `.env` on every deploy. Rebuild it from the full sample, never from a single key.
>
> With `has_env: true`, every deploy first checks on the runner that `APP_ENV` is set, is valid base64, and decodes to a non-empty file. With `env_sample` it also checks every required key. Any failure stops the deploy before the server is touched. `env_sample` without `has_env` fails, because no `.env` would be written. The `.env` on the server is written owner-only (`600`).

---

## Required Secrets

| Secret | Description |
|---|---|
| `SSH_HOST` | Server IP or hostname |
| `SSH_PORT` | SSH port (default `22`) |
| `SSH_USERNAME` | SSH deploy user |
| `SSH_PRIVATE_KEY` | SSH private key (PEM format) |
| `SSH_FINGERPRINT` | SHA256 fingerprint of the server's host key — get with `ssh-keyscan <host> \| ssh-keygen -lf - -E sha256` (use the ED25519 value) |

`GITHUB_TOKEN` is provided automatically by GitHub Actions — no configuration needed.

### Bulk-setting secrets across all repos

Use the provided script to push all secrets in one shot:

**PowerShell (Windows — recommended):**
```powershell
# 1. Fill in your values
copy scripts\secrets.conf.example scripts\secrets.conf
# edit scripts\secrets.conf

# 2. Run (requires GitHub CLI: https://cli.github.com)
.\scripts\set-secrets.ps1                    # Process all repos
.\scripts\set-secrets.ps1 mysql redis        # Process only specific repos
```

> If blocked by execution policy, run once: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

**Bash (WSL / Linux / macOS):**
```bash
cp scripts/secrets.conf.example scripts/secrets.conf
# edit scripts/secrets.conf
chmod +x scripts/set-secrets.sh
./scripts/set-secrets.sh                    # Process all repos
./scripts/set-secrets.sh mysql redis        # Process only specific repos
```

`secrets.conf` is gitignored — it will never be committed.

---

## Usage in a Project Repo

```yaml
# .github/workflows/ci-cd.yml
name: my-app CI/CD

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: Tuneup-Tech/ci-templates/.github/workflows/docker-build-push-deploy.yml@master
    with:
      image_name: my-app
      compose_service: app
      server_path: /srv/my-app
    secrets: inherit
```

---

## Projects Using These Templates

| Project | Template | Server Path |
|---|---|---|
| `fin-app` | `docker-build-push-deploy` | `/srv/fin-app` |
| `tuneuptech` | `docker-build-push-deploy` | `/srv/tuneuptech` |
| `true-cost-be` | `docker-build-push-deploy` | `/srv/true-cost-be` |
| `true-cost-fe` | `frontend-build-deploy` | `/srv/true-cost-fe` |
| `roundcircle` | `docker-build-push-deploy` | `/srv/roundcircle` |
| `traefik` | `infra-compose-deploy` | `/srv/traefik` |
| `uptime-kuma` | `infra-compose-deploy` | `/srv/uptime` |
| `authentik` | `infra-compose-deploy` | `/srv/authentik` |
| `firefly3` | `infra-compose-deploy` | `/srv/firefly3` |
| `mysql` | `infra-compose-deploy` | `/srv/mysql` |
| `phpmyadmin` | `infra-compose-deploy` | `/srv/phpmyadmin` |
| `portainer` | `infra-compose-deploy` | `/srv/portainer` |
| `rabbitmq` | `infra-compose-deploy` | `/srv/rabbitmq` |
| `redis` | `infra-compose-deploy` | `/srv/redis` |
| `chat` | `infra-compose-deploy` | `/srv/chat` |
