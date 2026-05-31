#!/bin/bash
input=$(cat)

# Model name — extract short name.
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
case "$model" in
  *sonnet*|*Sonnet*) model="Sonnet" ;;
  *opus*|*Opus*)     model="Opus" ;;
  *haiku*|*Haiku*)   model="Haiku" ;;
  *mimo*)            model="MiMo" ;;
esac

# Git branch.
dir=$(echo "$input" | jq -r '.workspace.current_dir // empty')
branch=""
if [ -n "$dir" ]; then
  branch=$(git -C "$dir" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
fi
branch_str=" | 🌿 $branch"
[ -z "$branch" ] && branch_str=""

# Project name — basename of project_dir or current_dir.
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // empty')
project=$(basename "$project_dir" 2>/dev/null)
project_str=" | 📂 $project"
[ -z "$project" ] && project_str=""

# Context window usage.
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  filled=$(( used_int / 10 ))
  empty=$(( 10 - filled ))
  bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++));  do bar+="░"; done
  ctx_str=" | ${bar} ${used_int}%"
fi

# Claude.ai 5h/7d rate limits when Claude Code provides them.
rate_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_str=""
if [ -n "$rate_5h" ]; then
  used_5h=$(printf '%.0f' "$rate_5h")
  rem_5h=$(( 100 - used_5h ))
  rate_str=" | 5h:${rem_5h}%"
fi
if [ -n "$rate_7d" ]; then
  used_7d=$(printf '%.0f' "$rate_7d")
  rem_7d=$(( 100 - used_7d ))
  rate_str="${rate_str} 7d:${rem_7d}%"
fi

# BigModel/GLM Claude Code uses a third-party Anthropic-compatible endpoint, so
# Claude Code may not populate .rate_limits. Query BigModel's quota endpoint as
# a cached fallback for GLM profiles.
if [ -z "$rate_str" ] && { [ "$CLAUDE_PROFILE" = "glm51" ] || echo "$model" | grep -qi '^glm'; }; then
  quota_cache="${TMPDIR:-/tmp}/claude-bigmodel-quota.json"
  quota_ttl="${CLAUDE_BIGMODEL_QUOTA_TTL:-60}"
  now_ts=$(date +%s)
  cache_ts=0
  if [ -f "$quota_cache" ]; then
    cache_ts=$(stat -f %m "$quota_cache" 2>/dev/null || stat -c %Y "$quota_cache" 2>/dev/null || echo 0)
  fi

  if [ ! -f "$quota_cache" ] || [ $(( now_ts - cache_ts )) -ge "$quota_ttl" ]; then
    python3 - "$quota_cache" >/dev/null 2>&1 <<'PY'
import json
import os
import sys
import urllib.request
from pathlib import Path

cache = Path(sys.argv[1])
token = os.environ.get("ANTHROPIC_AUTH_TOKEN") or os.environ.get("BIGMODEL_API_KEY")
if not token:
    config_path = Path(os.environ.get("OPENCLAW_CONFIG_PATH", "/Users/alex/.openclaw/openclaw.json"))
    data = json.loads(config_path.read_text())
    token = data["models"]["providers"]["zai"]["apiKey"]

request = urllib.request.Request(
    "https://open.bigmodel.cn/api/monitor/usage/quota/limit",
    headers={
        "Authorization": token,
        "Accept-Language": "en-US,en",
        "Content-Type": "application/json",
    },
)
with urllib.request.urlopen(request, timeout=5) as response:
    payload = json.loads(response.read().decode())
limits = payload.get("data", {}).get("limits", [])

result = {}
for item in limits:
    if item.get("type") != "TOKENS_LIMIT":
        continue
    unit = item.get("unit")
    number = item.get("number")
    percentage = item.get("percentage")
    reset_ms = item.get("nextResetTime")
    if unit == 3 and number == 5:
        result["five_hour_used_percentage"] = percentage
        result["five_hour_reset_ms"] = reset_ms
    elif unit == 6 and number == 1:
        result["seven_day_used_percentage"] = percentage
        result["seven_day_reset_ms"] = reset_ms

cache.write_text(json.dumps(result, separators=(",", ":")) + "\n")
cache.chmod(0o600)
PY
  fi

  if [ -f "$quota_cache" ]; then
    bm_5h=$(jq -r '.five_hour_used_percentage // empty' "$quota_cache" 2>/dev/null)
    bm_7d=$(jq -r '.seven_day_used_percentage // empty' "$quota_cache" 2>/dev/null)
    if [ -n "$bm_5h" ]; then
      bm_used_5h=$(printf '%.0f' "$bm_5h")
      bm_rem_5h=$(( 100 - bm_used_5h ))
      rate_str=" | 5h:${bm_rem_5h}%"
    fi
    if [ -n "$bm_7d" ]; then
      bm_used_7d=$(printf '%.0f' "$bm_7d")
      bm_rem_7d=$(( 100 - bm_used_7d ))
      rate_str="${rate_str} 7d:${bm_rem_7d}%"
    fi
  fi
fi

# Context window remaining.
ctx_rem=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
ctx_rem_str=""
if [ -n "$ctx_rem" ]; then
  ctx_rem_int=$(printf '%.0f' "$ctx_rem")
  ctx_rem_str=" | ctx:${ctx_rem_int}%"
fi

printf "🤖 %s%s%s%s%s%s" "$model" "$branch_str" "$project_str" "$ctx_str" "$rate_str" "$ctx_rem_str"
