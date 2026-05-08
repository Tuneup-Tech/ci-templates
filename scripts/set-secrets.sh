#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# set-secrets.sh
# Pushes GitHub Actions secrets to every repo listed in secrets.conf.
#
# Prerequisites:
#   - GitHub CLI installed and authenticated: gh auth login
#   - secrets.conf filled in (copy secrets.conf.example → secrets.conf)
#
# Usage:
#   chmod +x set-secrets.sh
#   ./set-secrets.sh
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/secrets.conf"

# --- Validate config file exists -------------------------------------------
if [[ ! -f "$CONF_FILE" ]]; then
  echo "❌  secrets.conf not found."
  echo "    Copy scripts/secrets.conf.example to scripts/secrets.conf and fill it in."
  exit 1
fi

source "$CONF_FILE"

# --- Validate required variables -------------------------------------------
: "${SSH_HOST:?SSH_HOST is not set in secrets.conf}"
: "${SSH_PORT:?SSH_PORT is not set in secrets.conf}"
: "${SSH_USERNAME:?SSH_USERNAME is not set in secrets.conf}"
: "${SSH_KEY_FILE:?SSH_KEY_FILE is not set in secrets.conf}"
: "${REPOS:?REPOS array is not set in secrets.conf}"

# --- Validate key file exists -----------------------------------------------
if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "❌  SSH key file not found: $SSH_KEY_FILE"
  exit 1
fi

# --- Validate gh CLI is installed and authenticated -------------------------
if ! command -v gh &>/dev/null; then
  echo "❌  GitHub CLI (gh) is not installed."
  echo "    Install it from https://cli.github.com"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "❌  Not authenticated with GitHub CLI. Run: gh auth login"
  exit 1
fi

# --- Collect secret values --------------------------------------------------
SSH_PRIVATE_KEY=$(cat "$SSH_KEY_FILE")

echo ""
echo "🔐 Pushing secrets to ${#REPOS[@]} repos..."
echo "   Host  : $SSH_HOST:$SSH_PORT"
echo "   User  : $SSH_USERNAME"
echo "   Key   : $SSH_KEY_FILE"
echo ""

# --- Push secrets -----------------------------------------------------------
FAILED=()

for repo in "${REPOS[@]}"; do
  echo "→ $repo"
  if gh secret set SSH_HOST          --body "$SSH_HOST"          --repo "$repo" \
  && gh secret set SSH_PORT          --body "$SSH_PORT"          --repo "$repo" \
  && gh secret set SSH_USERNAME      --body "$SSH_USERNAME"      --repo "$repo" \
  && gh secret set SSH_PRIVATE_KEY   --body "$SSH_PRIVATE_KEY"   --repo "$repo"; then
    echo "  ✅ done"
  else
    echo "  ❌ failed"
    FAILED+=("$repo")
  fi
  echo ""
done

# --- Summary ----------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "✅  All secrets set successfully."
else
  echo "⚠️   Completed with failures:"
  for r in "${FAILED[@]}"; do
    echo "    - $r"
  done
  echo ""
  echo "    Common causes:"
  echo "    • Repo doesn't exist yet on GitHub"
  echo "    • You don't have admin access to that repo"
  exit 1
fi
