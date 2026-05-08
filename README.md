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
.\scripts\set-secrets.ps1
```

> If blocked by execution policy, run once: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

**Bash (WSL / Linux / macOS):**
```bash
cp scripts/secrets.conf.example scripts/secrets.conf
# edit scripts/secrets.conf
chmod +x scripts/set-secrets.sh
./scripts/set-secrets.sh
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
    uses: Tuneup-Tech/ci-templates/.github/workflows/docker-build-push-deploy.yml@main
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
