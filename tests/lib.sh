#!/usr/bin/env bash
# Tiny test harness (no external framework). Sourced by tests/test_*.sh.
# Every test file gets a fresh sandbox HOME; nothing outside it is touched.
# shellcheck shell=bash
TESTS_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC2034 # used by the sourcing test files
ROOT=$(cd "$TESTS_DIR/.." && pwd)
PASS=0 FAIL=0

# Drop any GIT_* variables inherited from a calling git hook / CI.
for _v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$_v"; done

t_init() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX") || exit 1
  T=$(cd "$T" && pwd -P)
  trap 't_cleanup' EXIT
  export HOME=$T/home XDG_CONFIG_HOME=$T/home/.config XDG_STATE_HOME=$T/home/.local/state
  export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
  export GIT_SYNC_LOG=$T/git-sync.log GIT_SYNC_BACKUP_DIR=$T/home/local/backups
  export DOTFILES_SECRET_SCANNER=builtin DOTFILES_SKIP_LAUNCHCTL=1
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  mkdir -p "$HOME" "$T/remotes" "$T/work"
  # Keep the real PATH minus anything that would call out (no gitleaks surprises).
}
t_cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; }

# newhome NAME: switch to a fresh empty sandbox HOME (with XDG dirs under it).
newhome() {
  export HOME=$T/$1 XDG_CONFIG_HOME=$T/$1/.config XDG_STATE_HOME=$T/$1/.local/state
  mkdir -p "$HOME"
}
# snapshot DIR: names, file checksums and link targets (byte-level identity check)
snapshot() {
  (
    cd "$1" && find . | LC_ALL=C sort
    find . -type f -exec cksum {} + | LC_ALL=C sort
    find . -type l -exec sh -c 'for l; do echo "$l -> $(readlink "$l")"; done' _ {} + | LC_ALL=C sort
  )
}

ok() {
  PASS=$((PASS + 1))
  printf '  ok   %s\n' "$1"
}
bad() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1"
  [ -n "${2:-}" ] && printf '       %s\n' "$2" | head -n 8
}

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}
assert_contains() { # name haystack needle
  case $2 in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$2]" ;; esac
}
assert_not_contains() {
  case $2 in *"$3"*) bad "$1" "unexpected [$3] in [$2]" ;; *) ok "$1" ;; esac
}
assert_file() { if [ -e "$2" ]; then ok "$1"; else bad "$1" "missing file $2"; fi; }
assert_no_file() { if [ ! -e "$2" ]; then ok "$1"; else bad "$1" "unexpected file $2"; fi; }

# run NAME EXPECTED_RC cmd... : captures OUT (stdout) ERR (stderr) RC
run() {
  local name=$1 want=$2
  shift 2
  OUT=$("$@" 2>"$T/stderr" </dev/null)
  RC=$?
  ERR=$(cat "$T/stderr")
  if [ "$RC" = "$want" ]; then ok "$name (rc=$RC)"; else bad "$name (rc=$RC, wanted $want)" "$OUT $ERR"; fi
}

json_valid() { # json_valid NAME STRING
  if command -v jq >/dev/null 2>&1; then
    if printf '%s' "$2" | jq -e . >/dev/null 2>&1; then ok "$1: valid JSON"; else bad "$1: invalid JSON" "$2"; fi
  elif command -v python3 >/dev/null 2>&1; then
    if printf '%s' "$2" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "$1: valid JSON"; else bad "$1: invalid JSON" "$2"; fi
  else ok "$1: (no jq/python3, JSON check skipped)"; fi
}
jq_get() { # jq_get 'filter' STRING  (needs jq; prints empty if missing)
  command -v jq >/dev/null 2>&1 && printf '%s' "$2" | jq -r "$1" 2>/dev/null
}

# --- git fixtures -----------------------------------------------------------
# mk_remote NAME [SUBDIR] -> bare repo with one commit on main at $T/remotes/[SUBDIR/]NAME.git
mk_remote() {
  local dir=$T/remotes/${2:+$2/}$1.git seed=$T/seed-$1
  mkdir -p "$(dirname "$dir")"
  git init -q --bare -b main "$dir"
  git init -q -b main "$seed"
  (cd "$seed" && echo base >base.txt && git add base.txt && git -c core.hooksPath=/dev/null commit -q -m "chore: seed" &&
    git remote add origin "$dir" && git -c core.hooksPath=/dev/null push -q -u origin main)
  rm -rf "$seed"
  printf '%s\n' "$dir"
}
# clone_to REMOTE_DIR DEST
clone_to() { git -c core.hooksPath=/dev/null clone -q "$1" "$2" 2>/dev/null; }
# commit_file REPO FILE CONTENT MSG  (hooks bypassed: used for fixtures only)
commit_file() {
  (cd "$1" && printf '%s\n' "$3" >"$2" && git add "$2" && git -c core.hooksPath=/dev/null commit -q -m "$4")
}
# push_from REPO BRANCH
push_from() { (cd "$1" && git -c core.hooksPath=/dev/null push -q origin "$2" 2>/dev/null); }

summary() {
  printf '%s: %s passed, %s failed\n' "$(basename "$0")" "$PASS" "$FAIL"
  [ "$FAIL" = 0 ]
}
