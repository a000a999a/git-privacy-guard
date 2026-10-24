#!/usr/bin/env bash
# Installs privacy-guard for the current user: global git hooks for every repo, a private
# config dir, and a daily systemd user timer that refreshes the title list.
#   ./install.sh              install / update
#   ./install.sh --uninstall  remove the global hooks and the timer (keeps your private lists)
set -euo pipefail

GUARD_HOME="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONF_DIR="${PRIVACY_GUARD_CONFIG:-$HOME/.config/git-privacy-guard}"
UNIT_DIR="$HOME/.config/systemd/user"

if [ "${1:-}" = --uninstall ]; then
    if [ "$(git config --global --get core.hooksPath || true)" = "$GUARD_HOME/hooks" ]; then
        git config --global --unset core.hooksPath
        echo "Removed global core.hooksPath."
    fi
    systemctl --user disable --now privacy-guard-titles.timer 2>/dev/null || true
    rm -f "$UNIT_DIR/privacy-guard-titles.service" "$UNIT_DIR/privacy-guard-titles.timer"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "Uninstalled. Your private lists in $CONF_DIR were left in place."
    exit 0
fi

GITLEAKS="$(command -v gitleaks || echo "$HOME/.local/bin/gitleaks")"
[ -x "$GITLEAKS" ] || { echo "gitleaks not found (PATH or ~/.local/bin) -- install it first."; exit 1; }

current="$(git config --global --get core.hooksPath || true)"
if [ -n "$current" ] && [ "$current" != "$GUARD_HOME/hooks" ]; then
    echo "core.hooksPath is already set to '$current' -- not overwriting it."
    exit 1
fi

chmod 755 "$GUARD_HOME"/bin/* "$GUARD_HOME"/hooks/*
install -d -m 700 "$CONF_DIR"
for f in denylist allowlist; do
    [ -f "$CONF_DIR/$f.txt" ] || { install -m 600 "$GUARD_HOME/examples/$f.example.txt" "$CONF_DIR/$f.txt"; echo "Created $CONF_DIR/$f.txt -- edit it."; }
done
[ -f "$CONF_DIR/sources.json" ] || { install -m 600 "$GUARD_HOME/examples/sources.example.json" "$CONF_DIR/sources.json"; echo "Created $CONF_DIR/sources.json -- edit it."; }

git config --global core.hooksPath "$GUARD_HOME/hooks"
echo "Global hooks: core.hooksPath = $GUARD_HOME/hooks"

install -d "$UNIT_DIR"
cat > "$UNIT_DIR/privacy-guard-titles.service" <<EOF
[Unit]
Description=privacy-guard: refresh the private title list

[Service]
Type=oneshot
ExecStart=/usr/bin/env python3 $GUARD_HOME/bin/update-titles
EOF
cat > "$UNIT_DIR/privacy-guard-titles.timer" <<EOF
[Unit]
Description=privacy-guard: refresh the private title list daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now privacy-guard-titles.timer
echo "Daily title refresh: privacy-guard-titles.timer enabled"

"$GUARD_HOME/bin/update-titles" || echo "update-titles failed -- check $CONF_DIR/sources.json"
echo "Done. Test it in any repo with: $GUARD_HOME/bin/privacy-guard audit"
