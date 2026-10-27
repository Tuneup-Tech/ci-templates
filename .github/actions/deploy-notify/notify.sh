#!/usr/bin/env bash
# One Telegram message per deploy: status, what changed since last good
# deploy, failed step + error line. Never fails the run -- a notify hiccup
# must not turn a good deploy red.
# env: GH_TOKEN REPO RUN_ID RUN_ATTEMPT REF_NAME SHA APP DEPLOY LIVENESS
#      TG_TOKEN TG_CHAT. DRY_RUN=1 prints instead of sending.
# json via gh --jq (built-in), no separate jq needed.
set -uo pipefail

if [ "${DRY_RUN:-}" != "1" ] && { [ -z "${TG_TOKEN:-}" ] || [ -z "${TG_CHAT:-}" ]; }; then
  echo "::notice::TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID not set -- no deploy message"
  exit 0
fi

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
q() { gh api "$1" --jq "$2" 2>/dev/null || true; }

RUN_API="repos/$REPO/actions/runs/$RUN_ID"
RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"
SHORT=${SHA:0:7}
APP_H=$(printf '%s' "$APP" | esc)

dur=""
started=$(q "$RUN_API" '.run_started_at // empty')
if [ -n "$started" ]; then
  secs=$(( $(date +%s) - $(date -d "$started" +%s) ))
  dur=" in $((secs / 60))m$((secs % 60))s"
fi

case "$DEPLOY" in
  success)
    head="✅ <b>$APP_H deployed</b>$dur"
    if [ "${LIVENESS:-0}" -gt 0 ] 2>/dev/null; then head="$head, stayed up ${LIVENESS}s"; fi
    ;;
  cancelled) head="⚪ <b>$APP_H deploy cancelled</b>" ;;
  skipped) head="⚪ <b>$APP_H deploy skipped</b>" ;;
  *) head="❌ <b>$APP_H deploy FAILED</b>" ;;
esac

# failed step + error line. attempt-scoped so a rerun reports its own failure.
fail=""
if [ "$DEPLOY" = "failure" ]; then
  JOBS_API="$RUN_API/attempts/$RUN_ATTEMPT/jobs"
  step=$(q "$JOBS_API" '[.jobs[]? as $j | $j.steps[]? | select(.conclusion=="failure") | "\($j.name) → \(.name)"][0] // empty')
  job_id=$(q "$JOBS_API" '[.jobs[]? | select(.conclusion=="failure") | .id][0] // empty')
  err=""
  if [ -n "$job_id" ]; then
    err=$(q "repos/$REPO/check-runs/$job_id/annotations" \
      '[.[]? | select(.annotation_level=="failure") | .message | select(test("Process completed with exit code") | not)][0] // empty')
    if [ -z "$err" ]; then
      # ssh action output no become annotation. last error-ish log line instead.
      log=$(gh api "repos/$REPO/actions/jobs/$job_id/logs" 2>/dev/null \
        | sed -E 's/^[0-9]{4}-[0-9T:.-]+Z //' | grep -vE 'Process completed with exit code|^##\[' || true)
      # real error first ("Error: X is not set"), generic "command failed" last resort
      err=$(printf '%s\n' "$log" | grep -E '::error::|Error:|not set|No such|denied|refused' | tail -n 1 || true)
      [ -n "$err" ] || err=$(printf '%s\n' "$log" | grep -iE 'error|failed' | tail -n 1 || true)
      err=${err#*::error::}
    fi
  fi
  # server-side values no be github secrets -> not masked. scrub obvious ones.
  err=$(printf '%s' "$err" | sed -E -e 's#://[^:/@ ]+:[^@ ]+@#://***@#g' \
    -e 's/((key|secret|token|password|passwd|dsn)[A-Za-z_]*[=:][[:space:]]*)[^[:space:]]+/\1***/Ig')
  [ -n "$step" ] && fail="Failed at: <b>$(printf '%s' "$step" | esc)</b>"
  [ -n "$err" ] && fail="$fail
<code>$(printf '%s' "$err" | cut -c1-300 | esc)</code>"
fi

# what changed: this sha vs last successful run of same workflow + branch
changes=""
wf=$(q "$RUN_API" '.workflow_id // empty')
created=$(q "$RUN_API" '.created_at // empty')
prev=""
if [ -n "$wf" ]; then
  # last good deploy BEFORE this run. RUN_ID/created from github api, safe to inline
  prev=$(q "repos/$REPO/actions/workflows/$wf/runs?status=success&branch=$REF_NAME&per_page=20" \
    "[.workflow_runs[]? | select(.id != $RUN_ID and .created_at < \"$created\")][0].head_sha // empty")
fi
if [ -z "$prev" ]; then
  changes="(no earlier successful deploy to compare against)"
elif [ "$prev" = "$SHA" ]; then
  changes="Re-run: same code as last good deploy."
else
  CMP_API="repos/$REPO/compare/$prev...$SHA"
  # real PRs; release wrappers (from */development|master|main) skipped
  list=$(q "$CMP_API" '[.commits[]?.commit.message
    | select(startswith("Merge pull request #"))
    | capture("^Merge pull request #(?<n>[0-9]+) from (?<from>\\S+)\\n*(?<t>[^\\n]*)")
    | select(.from | test("/(development|master|main)$") | not)
    | "#\(.n) \(if .t == "" then .from else .t end)"] | reverse | .[]')
  if [ -z "$list" ]; then
    list=$(q "$CMP_API" '[.commits[]?.commit.message | split("\n")[0] | select(startswith("Merge pull request #") | not)] | reverse | .[]')
  fi
  total=$(printf '%s\n' "$list" | grep -c . || true)
  if [ "$total" -eq 0 ]; then
    changes="(no commits between ${prev:0:7} and $SHORT)"
  else
    changes=$(printf '%s\n' "$list" | head -n 12 | esc | sed 's/^/• /')
    [ "$total" -gt 12 ] && changes="$changes
…and $((total - 12)) more"
  fi
fi

text="$head
<code>$(printf '%s' "$REPO" | esc)@$SHORT</code>"
[ -n "$fail" ] && text="$text

$fail"
text="$text

$changes

<a href=\"$RUN_URL\">Open run</a>"

if [ "${DRY_RUN:-}" = "1" ]; then
  printf '%s\n' "$text"
  exit 0
fi

send() {
  curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
    "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT" \
    --data-urlencode "disable_web_page_preview=true" "$@" 2>/dev/null || true
}
code=$(send --data-urlencode "parse_mode=HTML" --data-urlencode "text=$text")
if [ "$code" = "400" ]; then
  # html rejected (odd char slipped through). failure msg matter most -> resend plain.
  plain=$(printf '%s' "$text" | sed -E 's/<[^>]+>//g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g')
  code=$(send --data-urlencode "text=$plain
$RUN_URL")
fi
[ "$code" = "200" ] || echo "::warning::Telegram deploy message not sent (HTTP ${code:-none})"
exit 0
