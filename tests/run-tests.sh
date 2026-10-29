#!/usr/bin/env bash
# End-to-end tests: real git repos and a local bare remote, all under a temp dir, with
# their own private lists and git config -- nothing on the machine is touched.
# A local remote counts as public (unknown visibility), so pushes with findings must fail.
set -uo pipefail

GUARD_HOME="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export PRIVACY_GUARD_CONFIG="$T/conf" XDG_CACHE_HOME="$T/cache"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GH=/nonexistent    # never ask GitHub during tests
mkdir -p "$PRIVACY_GUARD_CONFIG"
git config --global core.hooksPath "$GUARD_HOME/hooks"
git config --global user.name tester
git config --global user.email tester@example.invalid
git config --global init.defaultBranch main
printf '%s\n' '\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b' '\bsecret-host\b' > "$PRIVACY_GUARD_CONFIG/denylist.txt"
printf '%s\n' 'Test Movie Title' 'Café Example' > "$PRIVACY_GUARD_CONFIG/titles.txt"
: > "$PRIVACY_GUARD_CONFIG/allowlist.txt"
echo "PUSH_TIME_GATE=false" > "$PRIVACY_GUARD_CONFIG/guard.conf"

pass=0 fail=0
ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }
expect() { # expect <0|1> <description> <command...>
    local want=$1 desc=$2; shift 2
    if "$@" > "$T/out" 2>&1; then got=0; else got=1; fi
    if [ "$got" = "$want" ]; then ok "$desc"; else bad "$desc"; sed 's/^/        /' "$T/out"; fi
}

git init -q --bare "$T/remote.git"
git clone -q "$T/remote.git" "$T/work" 2>/dev/null
cd "$T/work"

echo "clean history"
echo "hello" > a.txt; git add a.txt
expect 0 "clean commit"                      git commit -q -m "first"
expect 0 "clean push to a public remote"     git push -q origin main

echo "private data in a file"
echo "server at 192.168.7.7" > b.txt; git add b.txt
expect 0 "commit only warns (default)"       git commit -q -m "add b"
grep -q "192.168.7.7" "$T/out" && ok "warning names the match" || bad "warning names the match"
expect 1 "push is blocked"                   git push -q origin main
echo "server at <host>" > b.txt; git add b.txt
expect 0 "amend after fixing"                git commit -q --amend -m "add b"
expect 0 "push passes after the fix"         git push -q origin main

echo "private data in a commit message"
echo "c" > c.txt; git add c.txt
expect 0 "commit with a title in the message" git commit -q -m "Fix import of Test Movie Title"
expect 1 "push is blocked (message)"         git push -q origin main
expect 0 "reword"                            git commit -q --amend -m "Fix import"
expect 0 "push passes after rewording"       git push -q origin main

echo "matching rules"
echo "Test Movie Titles and Untest Movie Title" > d.txt; git add d.txt   # no whole-phrase match
git commit -q -m "d" 2>/dev/null
expect 0 "partial words are not a match"     git push -q origin main
echo "Cafe Example" > e.txt; git add e.txt                              # titles are matched as given
git commit -q -m "e" 2>/dev/null
expect 0 "no accent folding at match time (update-titles adds folded variants)" git push -q origin main
echo "SECRET-HOST" > f.txt; git add f.txt
git commit -q -m "f" 2>/dev/null
expect 1 "denylist is case-insensitive"      git push -q origin main
echo "SECRET-HOST" > .privacy-guard-allow; git add .privacy-guard-allow
git commit -q -m "allow" 2>/dev/null
expect 0 "repo allowlist lets a false positive through" git push -q origin main

echo "secrets (gitleaks)"
tok="ghp_$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 36)"
echo "token = \"$tok\"" > g.txt; git add g.txt
git commit -q -m "g" 2>/dev/null
expect 1 "push with a GitHub token is blocked" git push -q origin main
git reset -q --hard HEAD~1

echo "time window"
echo "PUSH_TIME_GATE=true" > "$PRIVACY_GUARD_CONFIG/guard.conf"
echo "tw" > tw.txt; git add tw.txt; git commit -q -m "tw" 2>/dev/null
_PG_TEST_DOW=1 _PG_TEST_HOUR=10 expect 1 "push blocked on weekday morning"    git push -q origin main
_PG_TEST_DOW=5 _PG_TEST_HOUR=17 expect 1 "push blocked on Friday afternoon"   git push -q origin main
_PG_TEST_DOW=6 _PG_TEST_HOUR=10 expect 0 "push allowed on Saturday morning"   git push -q origin main
echo "tw2" > tw2.txt; git add tw2.txt; git commit -q -m "tw2" 2>/dev/null
_PG_TEST_DOW=3 _PG_TEST_HOUR=19 expect 0 "push allowed on Wednesday evening"  git push -q origin main
echo "tw3" > tw3.txt; git add tw3.txt; git commit -q -m "tw3" 2>/dev/null
_PG_TEST_DOW=7 _PG_TEST_HOUR=8  expect 0 "push allowed on Sunday morning"     git push -q origin main
echo "tw4" > tw4.txt; git add tw4.txt; git commit -q -m "tw4" 2>/dev/null
PG_TIME_OVERRIDE=1 _PG_TEST_DOW=1 _PG_TEST_HOUR=10 expect 0 "override lets a weekday-morning push through" git push -q origin main
echo "PUSH_TIME_GATE=false" > "$PRIVACY_GUARD_CONFIG/guard.conf"

echo "strict commit mode"
printf 'PUSH_TIME_GATE=false\nCOMMIT_MODE=block\n' > "$PRIVACY_GUARD_CONFIG/guard.conf"
echo "192.168.1.1" > h.txt; git add h.txt
expect 1 "commit is blocked in block mode"   git commit -q -m "h"
echo "PUSH_TIME_GATE=false" > "$PRIVACY_GUARD_CONFIG/guard.conf"; git reset -q

echo "new branch on the remote"
git checkout -q -b feature
echo "x" > i.txt; git add i.txt; git commit -q -m "i" 2>/dev/null
expect 0 "first push of a clean new branch"  git push -q origin feature
echo "via secret-host" > j.txt; git add j.txt; git commit -q -m "j" 2>/dev/null
git rm -q --cached .privacy-guard-allow; rm .privacy-guard-allow; git commit -q -m "drop allow" 2>/dev/null
expect 1 "new commits on that branch are scanned" git push -q origin feature

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
