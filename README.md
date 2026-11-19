# git-privacy-guard

Global git hooks that stop private data from reaching any remote — public or private.

Secret scanners catch API keys and tokens. They don't know that your LAN address, your
machine's host name, your home directory path, the movies in your library, or the town
you live in are just as private. This guard blocks all of it, on every push, to every
remote.

## What it blocks

| Category | Examples | How it's caught |
|---|---|---|
| **Secrets** | API keys, tokens, passwords, private keys | [gitleaks](https://github.com/gitleaks/gitleaks) with its default rules |
| **Network addresses** | Private IPs (`192.168.*`, `10.*`), Tailscale CGNAT (`100.64.*`) | denylist regex |
| **Host names** | Your machines' names, internal DNS | denylist regex |
| **Paths and usernames** | `/home/you`, your e-mail address | denylist regex |
| **Media titles** | Movie and series names from your library (Radarr, Sonarr, Transmission, NAS folders) | auto-generated title list, matched as whole phrases |
| **Torrent artifacts** | Site names, magnet links, 40-character info hashes | denylist regex |
| **Places** | Town names, addresses, locations you don't want tied to your account | denylist regex |
| **Work-hour timestamps** | Daytime commit times that reveal when you're working on personal projects | post-commit redate to evening |
| **Work-hour pushes** | Pushes during office hours | time-window gate (weekends and evenings only) |

Everything above is checked against **added lines**, **commit messages**, and
**annotated tag messages** in the outgoing commits — not just the latest commit but every
commit in the push range.

## How it works

Four hooks run automatically on every git operation:

| Hook | When | Action |
|---|---|---|
| `pre-commit` | you run `git commit` | scans staged changes — **warns** (configurable to block) |
| `commit-msg` | after you write the message | scans the commit message — **warns** (configurable to block) |
| `post-commit` | after the commit is created | redates work-hour timestamps to evening — **automatic** |
| `pre-push` | you run `git push` | time-window check + full content scan of every outgoing commit — **blocks** on any finding |

The pre-push hook is the hard gate. Local commits warn early so you can fix things before
pushing, but nothing leaves the machine until the push scan passes.

Findings block regardless of whether the remote is public or private — private repos are
not exempt.

## Install

Needs gitleaks on `PATH` or in `~/.local/bin`, Python 3.10+, and `gh` (for the
visibility check).

```bash
./install.sh             # sets git config --global core.hooksPath, creates the config dir, enables the timer
./install.sh --uninstall # removes the global hooks and the timer, keeps your lists
```

With a global `core.hooksPath`, git stops running hooks from each repo's `.git/hooks/`.
The guard runs a repo's own `pre-commit`, `commit-msg` and `pre-push` hooks after its own
checks; other hook types in `.git/hooks/` are not run.

## Getting started

After running `install.sh`, the hooks are active but have no private lists yet — only
gitleaks secret scanning runs out of the box. The next steps set up your personal filters.

### 1. Create your denylist

Copy the example and fill in your own values:

```bash
cp examples/denylist.example.txt ~/.config/git-privacy-guard/denylist.txt
chmod 600 ~/.config/git-privacy-guard/denylist.txt
```

Edit `denylist.txt` with one extended regex per line (case-insensitive). Think about what
identifies you or your environment:

| What to add | Example regex | Why |
|---|---|---|
| Your LAN ranges | `\b192\.168\.1\.[0-9]{1,3}\b` | Reveals your network layout |
| Your machines' host names | `\bmy-server\b` | Ties repos to a physical machine |
| Your home directory | `/home/yourname\b` | Reveals your username and OS |
| Your private e-mail | `you@example\.com` | Links repos to your identity |
| Torrent sites and indexers | `\b(1337x\|rarbg\|thepiratebay)\b` | Reveals download habits |
| Magnet links | `magnet:\?xt=` | Contains torrent info hashes |
| Info hashes (40 hex chars) | `\b[0-9a-fA-F]{40}\b` | Identifies specific downloads |
| Place names | `\b(your-town\|your-street)\b` | Reveals your physical location |
| Tailscale / VPN ranges | `\b100\.(6[4-9]\|[7-9][0-9]\|1[01][0-9]\|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b` | Reveals your VPN topology |

See `examples/denylist.example.txt` for a full starting point.

### 2. Set up title scanning (optional)

If you run Radarr, Sonarr, or Transmission, the guard can auto-build a list of your media
titles so they never leak into commit messages or code comments.

```bash
cp examples/sources.example.json ~/.config/git-privacy-guard/sources.json
chmod 600 ~/.config/git-privacy-guard/sources.json
```

Edit `sources.json` with your actual URLs and paths:

```json
{
  "arr": [
    {"kind": "radarr", "url": "http://localhost:7878", "config_xml": "/path/to/radarr/config.xml"},
    {"kind": "sonarr", "url": "http://localhost:8989", "config_xml": "/path/to/sonarr/config.xml"}
  ],
  "transmission": "http://localhost:9091/transmission/rpc",
  "folders": [
    {"path": "/path/to/downloads", "depth": 2},
    {"path": "/mnt/nas/movies", "depth": 1}
  ]
}
```

Then generate the initial title list:

```bash
bin/update-titles
```

The installer sets up a daily systemd timer to keep it fresh. Titles are matched as whole
phrases (case-insensitive), so "The Matrix" matches but "Matrix" alone does not (unless
it's 8+ characters, then it's kept as a one-word title).

You can also skip this step and manage `titles.txt` by hand — just put one title per line.

### 3. Create your allowlist

Some harmless text will match your rules. For example, `\b[0-9a-fA-F]{40}\b` catches
every git commit hash. Add known-safe values to the global allowlist:

```bash
cp examples/allowlist.example.txt ~/.config/git-privacy-guard/allowlist.txt
chmod 600 ~/.config/git-privacy-guard/allowlist.txt
```

For false positives specific to one repo, add the exact matched text to a
`.privacy-guard-allow` file in that repo's root (this file is committed, so it must only
contain harmless text). For gitleaks false positives, add the fingerprint to
`.gitleaksignore` in the repo root.

### 4. Configure the time window

By default, pushes are blocked on weekdays between 07:31 and 18:59 (local time), and
commits made during those hours are automatically redated to 19:00. To change the hours
or disable the gate:

```bash
cp examples/guard.conf.example ~/.config/git-privacy-guard/guard.conf
```

Edit `guard.conf`:

```bash
# PUSH_TIME_GATE=true        # set to false to disable entirely
# PUSH_EVENING_HOUR=19       # weekday pushes allowed from this hour onward
# PUSH_MORNING_HOUR=7        # weekday pushes allowed up to this hour...
# PUSH_MORNING_MIN=30        # ...and this minute (default: until 07:30)
# COMMIT_MODE=warn           # set to block to also block commits (not just warn)
```

For an urgent one-off push during restricted hours, prefix the command:

```bash
PG_TIME_OVERRIDE=1 git push origin main
```

This bypasses the time check only — content checks still run.

### 5. Test your setup

Run the built-in tests to make sure everything works:

```bash
tests/run-tests.sh
```

Then audit an existing repo to see what the guard would catch:

```bash
cd /path/to/your/repo
/path/to/git-privacy-guard/bin/privacy-guard audit            # scan tracked files
/path/to/git-privacy-guard/bin/privacy-guard audit --history  # scan entire history
```

## How each filter works

### Gitleaks (secrets)

[Gitleaks](https://github.com/gitleaks/gitleaks) runs on every push with its default rule
set. It detects API keys, tokens, passwords, private keys, and other secrets by pattern
matching. No configuration needed — it works out of the box if the `gitleaks` binary is
on your `PATH` or in `~/.local/bin`.

Gitleaks scans both the diff content and the commit range being pushed. If gitleaks is
missing, the guard prints a warning and continues (secrets won't be checked).

### Denylist (regex matching)

`denylist.txt` contains one extended regex per line. Each regex is matched
case-insensitively (`grep -E -i`) against every added line and every commit message in
the push range.

The guard scans only **added lines** in diffs (lines starting with `+`), not removed
lines or unchanged context. This means renaming or deleting a file won't trigger a match,
but adding a new file or editing a line to include a match will.

### Title list (whole-phrase matching)

`titles.txt` contains one title per line. Titles are matched as whole words
(`grep -w -F`, case-insensitive) against the same added lines and commit messages.

This means "The Matrix" won't match inside "TheMatrixReloaded" or "matrix multiplication",
but will match "based on The Matrix" or "fix The Matrix import".

Titles are auto-generated by `bin/update-titles` from your media sources:
- **Radarr / Sonarr**: fetches all movie and series titles via their local API
- **Transmission**: reads torrent names from the RPC endpoint
- **Folders**: scans download directories and NAS mounts for folder names

Release names are cleaned (`Some.Movie.2025.1080p.BluRay-GRP` → `Some Movie`),
accent-free variants are added (`Café` → also matches `Cafe`), and short single-word
titles (under 8 characters) are skipped to reduce false positives.

### Allowlists (false positive handling)

Two levels of allowlisting:

| Scope | File | Committed? |
|---|---|---|
| Global (all repos) | `~/.config/git-privacy-guard/allowlist.txt` | No — private |
| Per-repo | `.privacy-guard-allow` in the repo root | Yes — must be harmless |

Both are exact-match, case-insensitive. When the guard finds a match in a line, it checks
whether the matched text appears in the allowlist. If it does, the finding is suppressed.

### Time-window gate

The pre-push hook checks the current day and time before allowing a push:

| Day | Allowed hours |
|---|---|
| Monday – Friday | 19:00 – 07:30 (configurable) |
| Saturday – Sunday | All day |

Pushes outside the allowed window are blocked with a message showing the current time and
the allowed range. `PG_TIME_OVERRIDE=1` bypasses this check for one push.

### Timestamp redating

The post-commit hook fires after every commit. If the commit was made on a weekday during
restricted hours (07:31 – 18:59 by default), it immediately amends the commit to set both
the author and committer timestamps to the evening hour (default 19:00) of the same day.

This is transparent — you'll see `privacy-guard: timestamp redated to 19:00` after the
commit. The content is unchanged; only the metadata timestamps shift. Weekend and
evening commits keep their real timestamps.

### Remote visibility detection

The guard calls `gh api repos/<owner>/<repo>` to check whether the target remote is
public or private (cached for 24 hours). This is informational — findings block regardless
of visibility. If `gh` is unavailable, the remote is treated as unknown (shown in output
but still blocked on findings).

## Claude Code: gatekeeper hook

`claude-code/git-bypass-guard.sh` is a Claude Code `PreToolUse` hook for the Bash tool.
It enforces the same push time window (weekends or weekdays 19:00–07:30) on any `git push`
command Claude runs, and asks for approval before commands that would skip git hooks
(`--no-verify`, `commit -n`), change `core.hooksPath`, force-push, or rewrite history
(`filter-repo`, `filter-branch`). It only reads the command text. Install it on the
machine where Claude Code runs:

```json
"hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
  { "type": "command", "command": "/home/<you>/.claude/hooks/git-bypass-guard.sh", "timeout": 10 } ] } ] }
```

The hook returns a **hard deny** for pushes outside the time window (cannot be
auto-approved), and an **ask** for security-sensitive operations (requires manual
approval each time).

## Private lists (never in git)

All in `~/.config/git-privacy-guard/` (mode 600). They list exactly what you want hidden,
so they must never be committed anywhere; `.gitignore` and CI in this repo guard against it.

| File | Content |
|---|---|
| `denylist.txt` | extended regexes, case-insensitive (see `examples/denylist.example.txt`) |
| `titles.txt` | generated by `bin/update-titles`, matched as whole phrases |
| `allowlist.txt` | exact texts that are fine everywhere (placeholders) |
| `sources.json` | where `update-titles` reads titles from |
| `guard.conf` | optional overrides (see `examples/guard.conf.example`) |

## Title list

`bin/update-titles` collects movie and series titles from Radarr/Sonarr (API key read from
the app's own `config.xml` at run time), torrent names from Transmission, and folder
names under configured roots such as a NAS mount. It cleans release names
(`Some.Movie.2025.1080p.BluRay-GRP` becomes `Some Movie`), adds accent-free variants,
skips tracks, covers and category folders, and only keeps titles of two or more words,
or one word of at least 8 characters. The list only grows, so an offline source never
removes titles. A daily systemd user timer refreshes it.

## Use

```bash
bin/privacy-guard audit            # scan the tracked files of the current repo
bin/privacy-guard audit --history  # scan every commit and message in its history
tests/run-tests.sh                 # end-to-end tests in a temp dir
```

## Limits

- Hooks run on the machine where you commit and push. A push from another machine, or
  with hooks skipped, is not checked.
- Only text is checked; images and other binary files are not.
- A title list can only contain what its sources know about.
- Title matching is per-line. A title split across two lines by word wrapping will not be
  caught. Genericize titles yourself when writing prose for a guarded repo.
