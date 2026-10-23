#!/usr/bin/env bash
# Profiles (minimal | standard | strict) and per-feature switches, end to end
# through a bootstrapped sandbox HOME. Fake secrets are assembled at runtime.
. "$(dirname "$0")/lib.sh"
t_init
"$ROOT/bootstrap.sh" --name Test --email test@example.com >/dev/null || {
  echo "bootstrap failed"
  exit 1
}
export PATH="$HOME/.local/bin:$PATH"
export GIT_SYNC_DISABLE=1
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
OV=$XDG_CONFIG_HOME/dotfiles/config

R=$(mk_remote prof)
clone_to "$R" "$T/work/prof"
cd "$T/work/prof" || exit 1
aws="AK""IA$(printf 'ABCDEFGHIJKLMNOP')"

reset_cfg() { # clear every repo-local switch
  git config --local --remove-section hooks 2>/dev/null
  git config --local --remove-section dotfiles 2>/dev/null
  git config --file "$OV" --remove-section hooks 2>/dev/null
  git config --file "$OV" --remove-section dotfiles 2>/dev/null
  rm -f .git/git-sync.kick
}
# probes: each prints "block" or "pass"
p_msg() { git commit -q --allow-empty -m "not conventional" >/dev/null 2>&1 && echo pass || echo block; }
p_secret() {
  printf 'k = %s\n' "$aws" >s.txt
  git add s.txt
  git commit -q -m "chore: s" >/dev/null 2>&1 && echo pass || echo block
  git reset -q --soft HEAD~1 2>/dev/null
  git reset -q
  rm -f s.txt
}
p_branch() {
  git branch -q -f Bad_Name HEAD
  git push -q origin Bad_Name >/dev/null 2>&1 && {
    echo pass
    git push -q origin :Bad_Name >/dev/null 2>&1
  } || echo block
  git branch -q -D Bad_Name
}
p_main() {
  git checkout -q main 2>/dev/null
  git commit -q --allow-empty --no-verify -m "x"
  git push -q origin main >/dev/null 2>&1 && echo pass || echo block
  git reset -q --hard origin/main 2>/dev/null
}
p_sync() {
  mkdir -p "$T/stub"
  rm -f "$T/kick.log" .git/git-sync.kick
  printf '#!/bin/sh\necho "$@" >> "%s/kick.log"\n' "$T" >"$T/stub/git-sync"
  chmod +x "$T/stub/git-sync"
  PATH="$T/stub:$PATH" GIT_SYNC_DISABLE='' git commit -q --allow-empty --no-verify -m "x" >/dev/null 2>&1
  sleep 0.6
  [ -s "$T/kick.log" ] && echo pass || echo block
}
expect() { # expect NAME WANT GOT
  if [ "$3" = "$2" ]; then ok "$1: $2"; else bad "$1: wanted $2 got $3"; fi
}
matrix() { # matrix PROFILE msg secret branch main sync
  local prof=$1
  reset_cfg
  [ "$prof" = default ] || git config --local dotfiles.profile "$prof"
  expect "$prof commit-msg" "$2" "$(p_msg)"
  expect "$prof secret scan" "$3" "$(p_secret)"
  expect "$prof branch name" "$4" "$(p_branch)"
  expect "$prof push to main" "$5" "$(p_main)"
  expect "$prof sync trigger" "$6" "$(p_sync)"
}

echo "-- profile matrix (block = enforced, pass = not enforced)"
matrix minimal pass block pass pass block
matrix standard block block pass pass pass
matrix strict block block block block pass
echo "-- default profile (nothing configured) is standard"
matrix default block block pass pass pass
echo "-- unknown profile falls back to standard"
matrix bogus block block pass pass pass

echo "-- per-feature switches beat the profile (repo-local)"
reset_cfg
git config --local dotfiles.profile minimal
git config --local hooks.conventionalCommits true
expect "minimal + conventionalCommits=true" block "$(p_msg)"
reset_cfg
git config --local dotfiles.profile standard
git config --local hooks.conventionalCommits false
expect "standard + conventionalCommits=false" pass "$(p_msg)"
reset_cfg
git config --local hooks.secretScan false
expect "secretScan=false disables the scan" pass "$(p_secret)"
reset_cfg
git config --local hooks.branchName true
expect "standard + branchName=true" block "$(p_branch)"
reset_cfg
git config --local dotfiles.profile strict
git config --local hooks.branchName false
expect "strict + branchName=false (name)" pass "$(p_branch)"
expect "strict + branchName=false (main still protected)" block "$(p_main)"
reset_cfg
git config --local dotfiles.profile strict
git config --local hooks.protectMain false
expect "strict + protectMain=false" pass "$(p_main)"
expect "strict + protectMain=false (names still checked)" block "$(p_branch)"
reset_cfg
git config --local hooks.protectMain true
expect "standard + protectMain=true" block "$(p_main)"
reset_cfg
git config --local dotfiles.profile strict
git config --local hooks.sync false
expect "strict + sync=false" block "$(p_sync)"
reset_cfg
git config --local dotfiles.profile minimal
git config --local hooks.sync true
expect "minimal + sync=true" pass "$(p_sync)"

echo "-- global (overlay) setting, repo-local override beats it"
reset_cfg
git config --file "$OV" dotfiles.profile strict
expect "overlay strict applies" block "$(p_branch)"
git config --local dotfiles.profile minimal
expect "local minimal beats overlay strict (names)" pass "$(p_branch)"
expect "local minimal beats overlay strict (msg)" pass "$(p_msg)"
reset_cfg
git config --file "$OV" hooks.conventionalCommits false
expect "overlay switch off" pass "$(p_msg)"
git config --local hooks.conventionalCommits true
expect "local switch back on" block "$(p_msg)"

echo "-- hooks.branchNamePattern is configurable"
reset_cfg
git config --local dotfiles.profile strict
git config --local hooks.branchNamePattern '^(wip|team)/[a-z]+$'
git checkout -q -b team/alpha 2>/dev/null
if git push -q origin team/alpha >/dev/null 2>&1; then ok "custom pattern accepts team/alpha"; else bad "custom pattern accepts team/alpha"; fi
git checkout -q -b feat/12-default-style 2>/dev/null
if git push -q origin feat/12-default-style >/dev/null 2>&1; then bad "custom pattern rejects default style"; else ok "custom pattern rejects default style"; fi
assert_contains "message shows the active pattern" "$(git push origin feat/12-default-style 2>&1)" "^(wip|team)/[a-z]+\$"
git checkout -q main
git branch -q -D team/alpha feat/12-default-style

echo "-- main protection details and escape hatch"
reset_cfg
git config --local dotfiles.profile strict
git commit -q --allow-empty --no-verify -m "x"
if GIT_ALLOW_MAIN_PUSH=1 git push -q origin main >/dev/null 2>&1; then ok "GIT_ALLOW_MAIN_PUSH=1 allows a direct push"; else bad "escape hatch"; fi
git reset -q --hard HEAD~1
git commit -q --allow-empty --no-verify -m "y"
if GIT_ALLOW_MAIN_PUSH=1 git push -q --force origin main >/dev/null 2>&1; then bad "force-push stays blocked"; else ok "force-push stays blocked"; fi
git reset -q --hard origin/main

echo "-- exemption still beats every profile"
reset_cfg
git config --local dotfiles.profile strict
git remote add acme "$T/remotes/acme-corp/legacy.git" 2>/dev/null
git config --file "$OV" --add hooks.exemptOrigins '*[:/]acme-corp/*'
expect "strict, exempt origin: bad message passes" pass "$(p_msg)"
expect "strict, exempt origin: secret passes" pass "$(p_secret)"
git config --local hooks.exempt false
expect "hooks.exempt=false re-enables enforcement" block "$(p_msg)"
git config --local --unset hooks.exempt
GIT_HOOKS_EXEMPT=1 git commit -q --allow-empty -m "nope" >/dev/null 2>&1 && ok "GIT_HOOKS_EXEMPT=1 disables everything" || bad "GIT_HOOKS_EXEMPT=1"
git remote remove acme

echo "-- chaining still works with every feature off"
reset_cfg
git config --local hooks.secretScan false
git config --local hooks.conventionalCommits false
printf '#!/bin/sh\necho ran >> "%s/pc.log"\n' "$T" >.git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
git commit -q --allow-empty -m "whatever" >/dev/null 2>&1
assert_contains "repo pre-commit still runs" "$(cat "$T/pc.log" 2>/dev/null)" ran

summary
