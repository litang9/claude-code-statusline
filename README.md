# Claude Code Statusline

Personal Claude Code statusline with:

- model name normalization
- git branch and project name
- context window usage
- Claude.ai native 5h/7d rate limit display
- Kimi Code Coding Plan 5h/7d quota fallback
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
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

## Kimi Code Quota

Claude Code does not always populate `.rate_limits` when using Kimi Code's Anthropic-compatible endpoint. For Kimi profiles, this script queries:

```text
https://api.kimi.com/coding/v1/usages
```

It reads the token in this order:

1. `KIMI_CODE_API_KEY`
2. `ANTHROPIC_AUTH_TOKEN`
3. `ANTHROPIC_API_KEY`
4. `KIMI_API_KEY`
5. `MOONSHOT_API_KEY`
6. the same keys from `~/.claude/settings.kimi-k2.7.json` or `~/.claude/settings.json`

Quota responses are cached for 60 seconds in `${TMPDIR:-/tmp}/claude-kimi-code-usage.json`. Override with:

```bash
export CLAUDE_KIMI_CODE_USAGE_TTL=120
```

For Kimi Code, the statusline shows remaining quota like:

```text
🤖 Kimi | 📂 repo | ██░░░░░░░░ 20% | 5h:96% 7d:98%
```

## BigModel GLM Quota

Claude Code does not always populate `.rate_limits` when using an Anthropic-compatible third-party endpoint. For GLM profiles, this script queries:

```text
https://open.bigmodel.cn/api/monitor/usage/quota/limit
```

It reads the token in this order:

1. `ANTHROPIC_AUTH_TOKEN`
2. `BIGMODEL_API_KEY`
3. `models.providers.zai.apiKey` from `OPENCLAW_CONFIG_PATH`, defaulting to `~/.openclaw/openclaw.json`

Quota responses are cached for 60 seconds in `${TMPDIR:-/tmp}/claude-bigmodel-quota.json`. Override with:

```bash
export CLAUDE_BIGMODEL_QUOTA_TTL=120
```

For GLM, the statusline shows remaining quota like:

```text
🤖 GLM | 📂 repo | ██░░░░░░░░ 20% | 5h:96% 7d:99%
```
