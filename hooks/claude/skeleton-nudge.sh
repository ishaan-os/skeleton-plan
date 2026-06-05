#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook.
# Nudges the agent to produce a skeleton-plan on change/plan-shaped requests,
# and stays silent otherwise so it isn't noise on every message.
#
# Install: copy to ~/.claude/hooks/skeleton-nudge.sh, `chmod +x` it, and register
# it under "UserPromptSubmit" in ~/.claude/settings.json (see settings.snippet.json).
set -euo pipefail

prompt=$(cat | jq -r '.prompt // ""' | tr '[:upper:]' '[:lower:]')

# Don't double up if the user already invoked the skill explicitly.
case "$prompt" in *skeleton-plan*) exit 0 ;; esac

# Only nudge on change/plan-shaped requests.
if printf '%s' "$prompt" | grep -Eq '\b(plan|implement|refactor|add|change|build|migrate|rework)\b'; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Before proposing or writing changes, use the skeleton-plan skill: present a structural skeleton (file tree of new/modified/deleted files + typed signatures and docstrings of what you'll add or change, edits tagged with before->after signatures, bodies left as stubs). For larger plan-mode plans, embed it as an inline '## Skeleton' section."
  }
}
JSON
fi
exit 0
