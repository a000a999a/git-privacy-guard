#!/bin/sh
# Claude Code PreToolUse hook (Bash). Gates git pushes (time window + bypass detection)
# and blocks commands that would skip or weaken the privacy-guard hooks.
# It only reads the command text from the hook's JSON input; it runs nothing else.
input=$(cat)
m() { printf '%s' "$input" | /usr/bin/grep -Eq -e "$1"; }

security_reason=""
if m '--no-verify'; then
    security_reason="skips git hooks (--no-verify)"
elif m '\bcommit\b[^|;&"]*[[:space:]]-[a-mo-zA-Z]*n'; then
    security_reason="skips git hooks (git commit -n)"
elif m '\bpush\b[^|;&"]*[[:space:]](--force|-[a-zA-Z]*f|\+[^[:space:]])'; then
    security_reason="force push: rewrites history on the remote"
elif m 'filter-(repo|branch)'; then
    security_reason="rewrites git history (filter-repo / filter-branch)"
elif m 'core\.hooks[Pp]ath' && ! m '--get[^|;&"]*core\.hooks[Pp]ath'; then
    security_reason="changes core.hooksPath, which could switch off privacy-guard"
fi

# Time-window gate: HARD DENY outside allowed hours — cannot be auto-approved in any mode.
# Override: prefix the command with PG_TIME_OVERRIDE=1 after the user gives explicit approval.
time_reason=""
if m '\bgit\b.*\bpush\b'; then
    _dow=$(date +%u)
    _hour=$(date +%-H)
    _min=$(date +%-M)
    _blocked=0
    if [ "$_dow" -lt 6 ]; then
        if [ "$_hour" -ge 19 ] || [ "$_hour" -lt 7 ] || { [ "$_hour" -eq 7 ] && [ "$_min" -le 30 ]; }; then
            _blocked=0
        else
            _blocked=1
        fi
    fi
    if [ "$_blocked" -eq 1 ] && ! m '\bPG_TIME_OVERRIDE=1\b'; then
        time_reason="push outside allowed hours (weekdays 19:00-07:30 and weekends only). Now: $(date '+%A %H:%M'). To override: get explicit approval, then prefix the push command with PG_TIME_OVERRIDE=1"
    fi
fi

[ -z "$security_reason" ] && [ -z "$time_reason" ] && exit 0

if [ -n "$time_reason" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"git-bypass-guard: %s"}}\n' "$time_reason"
    exit 0
fi

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"git-bypass-guard: %s. Needs your approval."}}\n' "$security_reason"
