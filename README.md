# Claude Code Statusline

Personal Claude Code statusline with:

- model name normalization
- git branch and project name
- context window usage and remaining percentage
- Claude.ai native 5h/7d rate limit display
- BigModel GLM Coding Plan 5h/7d quota fallback

## Install

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then point Claude Code settings at the script:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /Users/alex/.claude/statusline.sh"
  }
}
```

## BigModel GLM Quota

Claude Code does not always populate `.rate_limits` when using an Anthropic-compatible third-party endpoint. For GLM profiles, this script queries:

```text
https://open.bigmodel.cn/api/monitor/usage/quota/limit
```

It reads the token in this order:

1. `ANTHROPIC_AUTH_TOKEN`
2. `BIGMODEL_API_KEY`
3. `models.providers.zai.apiKey` from `OPENCLAW_CONFIG_PATH`, defaulting to `/Users/alex/.openclaw/openclaw.json`

Quota responses are cached for 60 seconds in `${TMPDIR:-/tmp}/claude-bigmodel-quota.json`. Override with:

```bash
export CLAUDE_BIGMODEL_QUOTA_TTL=120
```

For GLM, the statusline shows remaining quota like:

```text
🤖 glm-5.1 | 📂 repo | ██░░░░░░░░ 20% | 5h:96% 7d:99% | ctx:80%
```
