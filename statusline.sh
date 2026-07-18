#!/bin/bash
input=$(cat)

# Format seconds as a short countdown: DdHh / HhMm / Mm / Ss.
format_countdown() {
  local sec=$1
  { [ -z "$sec" ] || [ "$sec" -le 0 ]; } && return
  local d=$(( sec / 86400 ))
  local h=$(( (sec % 86400) / 3600 ))
  local m=$(( (sec % 3600) / 60 ))
  local s=$(( sec % 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm'     "$m"
  else                      printf '%ds'     "$s"
  fi
}

# Build "REM% 🕙CD" from used-pct and reset-epoch-ms (either may be empty).
fmt_rate() {
  local used_pct=$1 reset_ms=$2
  [ -z "$used_pct" ] && return
  local used_int rem_int
  used_int=$(printf '%.0f' "$used_pct")
  rem_int=$(( 100 - used_int ))
  local out="${rem_int}%"
  if [ -n "$reset_ms" ] && [ "$reset_ms" -gt 0 ]; then
    local now_s reset_s rem_sec cd
    now_s=$(date +%s)
    reset_s=$(( reset_ms / 1000 ))
    rem_sec=$(( reset_s - now_s ))
    cd=$(format_countdown "$rem_sec")
    [ -n "$cd" ] && out="${out} 🕙 ${cd}"
  fi
  printf '%s' "$out"
}

# Model name — extract short name.
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
is_kimi=false
case "$model" in
  *kimi*|*Kimi*)   model="Kimi"; is_kimi=true ;;
  k3|K3)           model="K3"; is_kimi=true ;;
  *glm*|*GLM*)     model="GLM" ;;
  *sonnet*|*Sonnet*) model="Sonnet" ;;
  *opus*|*Opus*)     model="Opus" ;;
  *haiku*|*Haiku*)   model="Haiku" ;;
  *mimo*)            model="MiMo" ;;
esac
case "${CLAUDE_PROFILE:-}" in
  kimi|kimi-k2.7|kimi-code)
    [ "$is_kimi" = false ] && model="Kimi"
    is_kimi=true
    ;;
esac
case "${ANTHROPIC_MODEL:-}" in
  k3|K3) model="K3"; is_kimi=true ;;
  kimi*|Kimi*) model="Kimi"; is_kimi=true ;;
esac
if [ "$CLAUDE_PROFILE" = "glm51" ] || echo "${ANTHROPIC_MODEL:-}" | grep -qi '^glm'; then
  model="GLM"
fi

# Git branch.
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
branch=""
if [ -n "$dir" ]; then
  branch=$(git -C "$dir" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
fi
branch_str=" | 🌿 $branch"
[ -z "$branch" ] && branch_str=""

# Project name — basename of project_dir or current_dir.
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // empty')
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
rate_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at_ms // .rate_limits.five_hour.reset_at_ms // empty')
rate_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at_ms // .rate_limits.seven_day.reset_at_ms // empty')
rate_str=""
if [ -n "$rate_5h" ]; then
  rate_str=" | 5h:$(fmt_rate "$rate_5h" "$rate_5h_reset")"
fi
if [ -n "$rate_7d" ]; then
  rate_str="${rate_str} 7d:$(fmt_rate "$rate_7d" "$rate_7d_reset")"
fi

# Kimi Code has its own coding-plan quota endpoint. Claude Code usually does
# not fill .rate_limits for third-party Anthropic-compatible providers, so
# query Kimi Code's usage endpoint as a cached fallback.
if [ -z "$rate_str" ] && [ "$is_kimi" = true ]; then
  quota_cache="${TMPDIR:-/tmp}/claude-kimi-code-usage.json"
  quota_ttl="${CLAUDE_KIMI_CODE_USAGE_TTL:-60}"
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
import tempfile
import urllib.request
from pathlib import Path

cache = Path(sys.argv[1])
token = (
    os.environ.get("KIMI_CODE_API_KEY")
    or os.environ.get("ANTHROPIC_AUTH_TOKEN")
    or os.environ.get("ANTHROPIC_API_KEY")
    or os.environ.get("KIMI_API_KEY")
    or os.environ.get("MOONSHOT_API_KEY")
)
if not token:
    for name in ("settings.kimi-k2.7.json", "settings.json"):
        path = Path.home() / ".claude" / name
        if not path.exists():
            continue
        env = json.loads(path.read_text()).get("env", {})
        token = (
            env.get("KIMI_CODE_API_KEY")
            or env.get("ANTHROPIC_AUTH_TOKEN")
            or env.get("ANTHROPIC_API_KEY")
            or env.get("KIMI_API_KEY")
            or env.get("MOONSHOT_API_KEY")
        )
        if token:
            break
if not token:
    raise SystemExit(1)

base = os.environ.get("KIMI_CODE_BASE_URL", "https://api.kimi.com/coding/v1").rstrip("/")
url = os.environ.get("KIMI_CODE_USAGE_URL", f"{base}/usages")
request = urllib.request.Request(
    url,
    headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    },
)
with urllib.request.urlopen(request, timeout=5) as response:
    payload = json.loads(response.read().decode())

def as_record(value):
    return value if isinstance(value, dict) else {}

def to_num(value):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None

def pct_used(row):
    row = as_record(row)
    limit = to_num(row.get("limit"))
    used = to_num(row.get("used"))
    remaining = to_num(row.get("remaining"))
    if used is None and remaining is not None and limit is not None:
        used = max(0.0, limit - remaining)
    if used is None or limit is None or limit <= 0:
        return None
    return max(0.0, min(100.0, used / limit * 100.0))

def is_five_hour_limit(item):
    item = as_record(item)
    detail = as_record(item.get("detail")) or item
    window = as_record(item.get("window"))
    label = " ".join(
        str(v).lower()
        for v in (
            item.get("name"),
            item.get("title"),
            item.get("scope"),
            detail.get("name"),
            detail.get("title"),
            detail.get("scope"),
        )
        if v is not None
    )
    if "5h" in label or "5 hour" in label or "5-hour" in label:
        return True
    duration = to_num(window.get("duration") or item.get("duration") or detail.get("duration"))
    time_unit = str(window.get("timeUnit") or item.get("timeUnit") or detail.get("timeUnit") or "").upper()
    return (
        (duration == 300 and "MINUTE" in time_unit)
        or (duration == 5 and "HOUR" in time_unit)
    )

def reset_ms_of(*sources):
    """Best-effort reset timestamp across candidate records/fields.
    Accepts epoch-ms (>1e12), epoch-s (<1e12 -> x1000), numeric strings,
    or ISO 8601 strings (e.g. '2026-06-22T11:16:47Z')."""
    from datetime import datetime, timezone
    for src in sources:
        if not isinstance(src, dict):
            continue
        for key in ("nextResetTime", "resetAt", "resetsAt", "resetTime",
                    "reset_time", "expiresAt", "expireTime", "expiredAt"):
            v = src.get(key)
            if v is None:
                continue
            n = to_num(v)
            if n is not None and n > 0:
                return int(n * 1000) if n < 1e12 else int(n)
            if isinstance(v, str):
                try:
                    dt = datetime.fromisoformat(v.replace("Z", "+00:00"))
                    if dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    return int(dt.timestamp() * 1000)
                except ValueError:
                    continue
    return None

result = {}
seven_day = pct_used(payload.get("usage"))
if seven_day is not None:
    result["seven_day_used_percentage"] = seven_day
    sd_reset = reset_ms_of(payload.get("usage"), payload)
    if sd_reset is not None:
        result["seven_day_reset_ms"] = sd_reset

for item in payload.get("limits") or []:
    if not isinstance(item, dict) or not is_five_hour_limit(item):
        continue
    row = item.get("detail") if isinstance(item.get("detail"), dict) else item
    five_hour = pct_used(row)
    if five_hour is not None:
        result["five_hour_used_percentage"] = five_hour
        fh_reset = reset_ms_of(item, row, item.get("window") if isinstance(item.get("window"), dict) else {})
        if fh_reset is not None:
            result["five_hour_reset_ms"] = fh_reset
        break

cache.parent.mkdir(parents=True, exist_ok=True)
fd, tmp_name = tempfile.mkstemp(prefix=cache.name + ".", dir=str(cache.parent))
with os.fdopen(fd, "w") as f:
    json.dump(result, f, separators=(",", ":"))
    f.write("\n")
os.chmod(tmp_name, 0o600)
os.replace(tmp_name, cache)
PY
  fi

  if [ -f "$quota_cache" ]; then
    kimi_5h=$(jq -r '.five_hour_used_percentage // empty' "$quota_cache" 2>/dev/null)
    kimi_7d=$(jq -r '.seven_day_used_percentage // empty' "$quota_cache" 2>/dev/null)
    kimi_5h_reset=$(jq -r '.five_hour_reset_ms // empty' "$quota_cache" 2>/dev/null)
    kimi_7d_reset=$(jq -r '.seven_day_reset_ms // empty' "$quota_cache" 2>/dev/null)
    if [ -n "$kimi_5h" ]; then
      rate_str=" | 5h:$(fmt_rate "$kimi_5h" "$kimi_5h_reset")"
    fi
    if [ -n "$kimi_7d" ]; then
      rate_str="${rate_str} 7d:$(fmt_rate "$kimi_7d" "$kimi_7d_reset")"
    fi
  fi

  [ -z "$rate_str" ] && rate_str=" | 5h:-- 7d:--"
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
    config_path = Path(os.environ.get("OPENCLAW_CONFIG_PATH", str(Path.home() / ".openclaw" / "openclaw.json")))
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
    bm_5h_reset=$(jq -r '.five_hour_reset_ms // empty' "$quota_cache" 2>/dev/null)
    bm_7d_reset=$(jq -r '.seven_day_reset_ms // empty' "$quota_cache" 2>/dev/null)
    if [ -n "$bm_5h" ]; then
      rate_str=" | 5h:$(fmt_rate "$bm_5h" "$bm_5h_reset")"
    fi
    if [ -n "$bm_7d" ]; then
      rate_str="${rate_str} 7d:$(fmt_rate "$bm_7d" "$bm_7d_reset")"
    fi
  fi
fi

printf "🤖 %s%s%s%s%s" "$model" "$branch_str" "$project_str" "$ctx_str" "$rate_str"
