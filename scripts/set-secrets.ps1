# ---------------------------------------------------------------------------
# set-secrets.ps1
# Pushes GitHub Actions secrets to every repo listed in secrets.conf.
#
# Prerequisites:
#   - GitHub CLI installed and authenticated: gh auth login
#   - secrets.conf filled in (copy secrets.conf.example to secrets.conf)
#
# Usage (from PowerShell):
#   .\set-secrets.ps1
#
# If blocked by execution policy, run once:
#   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# ---------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfFile  = Join-Path $ScriptDir "secrets.conf"

# --- Validate config file exists --------------------------------------------
if (-not (Test-Path $ConfFile)) {
    Write-Host "ERROR: secrets.conf not found." -ForegroundColor Red
    Write-Host "       Copy scripts\secrets.conf.example to scripts\secrets.conf and fill it in."
    exit 1
}

# --- Parse secrets.conf (KEY="value" lines) ---------------------------------
$config = @{}
Get-Content $ConfFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^#' -or $line -eq '') { return }
    if ($line -match '^([A-Za-z0-9_]+)=(.+)$') {
        $val = $Matches[2].Trim().Trim('"').Trim("'")
        $config[$Matches[1]] = $val
    }
}

$SSH_HOST      = $config["SSH_HOST"]
$SSH_PORT      = $config["SSH_PORT"]
$SSH_USERNAME  = $config["SSH_USERNAME"]
$SSH_KEY_FILE  = $config["SSH_KEY_FILE"]
$PROJECTS_ROOT = $config["PROJECTS_ROOT"]

# --- Parse REPOS array (lines inside REPOS=( ... )) -------------------------
$inRepos = $false
$REPOS   = @()
Get-Content $ConfFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^REPOS=\(')                            { $inRepos = $true;  return }
    if ($line -eq ')')                                        { $inRepos = $false; return }
    if ($inRepos -and $line -ne '' -and $line -notmatch '^#') {
        $REPOS += $line.Trim('"').Trim("'")
    }
}

# --- Validate required values -----------------------------------------------
foreach ($key in @("SSH_HOST", "SSH_PORT", "SSH_USERNAME", "SSH_KEY_FILE")) {
    if (-not $config[$key]) {
        Write-Host "ERROR: $key is not set in secrets.conf" -ForegroundColor Red
        exit 1
    }
}
if ($REPOS.Count -eq 0) {
    Write-Host "ERROR: REPOS array is empty in secrets.conf" -ForegroundColor Red
    exit 1
}

# --- Validate key file exists -----------------------------------------------
if (-not (Test-Path $SSH_KEY_FILE)) {
    Write-Host "ERROR: SSH key file not found: $SSH_KEY_FILE" -ForegroundColor Red
    Write-Host "       Update SSH_KEY_FILE in secrets.conf to the correct Windows path."
    Write-Host "       Example: C:\Users\YourName\.ssh\id_ed25519"
    exit 1
}

# --- Validate gh CLI is installed and authenticated -------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: GitHub CLI (gh) is not installed." -ForegroundColor Red
    Write-Host "       Install it from https://cli.github.com"
    exit 1
}

gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Not authenticated. Run: gh auth login" -ForegroundColor Red
    exit 1
}

# --- Collect secret values --------------------------------------------------
$SSH_PRIVATE_KEY = Get-Content $SSH_KEY_FILE -Raw

Write-Host ""
Write-Host "Pushing secrets to $($REPOS.Count) repos..." -ForegroundColor Cyan
Write-Host "   Host : ${SSH_HOST}:${SSH_PORT}"
Write-Host "   User : $SSH_USERNAME"
Write-Host "   Key  : $SSH_KEY_FILE"
Write-Host ""

# --- Push secrets -----------------------------------------------------------
$failed = @()

foreach ($repo in $REPOS) {
    Write-Host "-> $repo" -ForegroundColor Yellow
    try {
        gh secret set SSH_HOST        --body $SSH_HOST            --repo $repo
        gh secret set SSH_PORT        --body $SSH_PORT            --repo $repo
        gh secret set SSH_USERNAME    --body $SSH_USERNAME        --repo $repo
        gh secret set SSH_PRIVATE_KEY --body $SSH_PRIVATE_KEY     --repo $repo

        # --- APP_ENV: look for .env.production ---
        $repoName    = ($repo -split '/')[-1]
        $overrideKey = "ENV_PATH_" + ($repoName -replace '-','_')
        if ($config[$overrideKey]) {
            $envFile = $config[$overrideKey]
        } else {
            $envFile = Join-Path $PROJECTS_ROOT "$repoName\.env.production"
        }
        if (Test-Path $envFile) {
            $encoded = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($envFile))
            gh secret set APP_ENV --body $encoded --repo $repo
            Write-Host "   APP_ENV set from $envFile" -ForegroundColor DarkCyan
        } else {
            Write-Host "   APP_ENV skipped (no .env.production found)" -ForegroundColor DarkGray
        }

        Write-Host "   OK" -ForegroundColor Green
    } catch {
        Write-Host "   FAILED: $_" -ForegroundColor Red
        $failed += $repo
    }
    Write-Host ""
}

# --- Summary ----------------------------------------------------------------
Write-Host "----------------------------------------"
if ($failed.Count -eq 0) {
    Write-Host "All secrets set successfully." -ForegroundColor Green
} else {
    Write-Host "Completed with failures:" -ForegroundColor Yellow
    foreach ($r in $failed) {
        Write-Host "  - $r" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Common causes:"
    Write-Host "  * Repo does not exist yet on GitHub"
    Write-Host "  * Insufficient admin access to that repo"
    exit 1
}
