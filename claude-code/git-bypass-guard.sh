#!/bin/sh
# Claude Code PreToolUse hook (Bash). Asks the user before any command that would skip or
# weaken git hooks (and with them privacy-guard) or rewrite history on a remote.
# It only reads the command text from the hook's JSON input; it runs nothing else.
input=$(cat)
m() { printf '%s' "$input" | /usr/bin/grep -Eq -e "$1"; }

reason=""
if m '--no-verify'; then
    reason="skips git hooks (--no-verify)"
elif m '\bcommit\b[^|;&"]*[[:space:]]-[a-mo-zA-Z]*n'; then
    reason="skips git hooks (git commit -n)"
elif m '\bpush\b[^|;&"]*[[:space:]](--force|-[a-zA-Z]*f|\+[^[:space:]])'; then
    reason="force push: rewrites history on the remote"
elif m 'filter-(repo|branch)'; then
    reason="rewrites git history (filter-repo / filter-branch)"
elif m 'core\.hooks[Pp]ath' && ! m '--get[^|;&"]*core\.hooks[Pp]ath'; then
    reason="changes core.hooksPath, which could switch off privacy-guard"
fi

[ -z "$reason" ] && exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"git-bypass-guard: %s. Needs your approval."}}\n' "$reason"
