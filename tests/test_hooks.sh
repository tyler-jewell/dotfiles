#!/usr/bin/env bash
# Global hook tests, run end to end through a bootstrapped sandbox HOME so
# core.hooksPath really points at git/hooks. Fake secrets are assembled at
# runtime so this file itself contains nothing a scanner would flag.
. "$(dirname "$0")/lib.sh"
t_init
"$ROOT/bootstrap.sh" --name "Test" --email "test@example.com" >/dev/null || {
  echo "bootstrap failed"
  exit 1
}
export PATH="$HOME/.local/bin:$PATH"
# The shipped default is profile=standard with no exemptions. These tests drive
# the strictest profile and an exempt org through the user overlay.
OV=$XDG_CONFIG_HOME/dotfiles/config
git config --file "$OV" dotfiles.profile strict
git config --file "$OV" --add hooks.exemptOrigins '*[:/]acme-corp/*'
export GIT_SYNC_DISABLE=1                                                     # no background sync noise; re-enabled for the kick tests
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL # identity now comes from the overlay

assert_eq "hooksPath resolved by git" "$HOME/.config/git/hooks" "$(cd / && git config --type=path core.hooksPath)"

R=$(mk_remote proj)
clone_to "$R" "$T/work/proj"
cd "$T/work/proj" || exit 1
git checkout -q -b feat/1-hooks 2>/dev/null

commit_msg_ok() { git commit -q --allow-empty -m "$1" >/dev/null 2>&1; }
echo "-- commit-msg: accepted"
for m in "feat: add thing" "fix(sync): handle gone" "feat!: drop v1" "chore(deps)!: bump" "docs: x" "style: x" "refactor: x" "perf: x" "test: x" "build: x" "ci: x" "revert: x" \
  "Merge branch 'x' into main" 'Revert "feat: x"' "fixup! feat: x" "squash! feat: x" "feat(a/b,c): multi scope"; do
  if commit_msg_ok "$m"; then ok "accept: $m"; else bad "accept: $m"; fi
done
if git commit -q --allow-empty -m "feat: with trailer" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" >/dev/null 2>&1; then ok "accept: Co-Authored-By trailer"; else bad "accept: trailer"; fi
echo "-- commit-msg: rejected"
for m in "added stuff" "feat:nospace" "Feat: caps" "feat(): empty scope" "unknown: x" "feat add" "WIP"; do
  if commit_msg_ok "$m"; then bad "reject: $m"; else ok "reject: $m"; fi
done
long=$(printf 'feat: %0101d' 0)
if commit_msg_ok "$long"; then bad "reject: header > 100 chars"; else ok "reject: header > 100 chars"; fi
err=$(git commit --allow-empty -m "nope" 2>&1)
assert_contains "reject prints fix hint" "$err" "Conventional Commit"
assert_contains "hint mentions bypass" "$err" "--no-verify"
if git commit -q --allow-empty --no-verify -m "nope" >/dev/null 2>&1; then ok "--no-verify bypasses commit-msg"; else bad "--no-verify bypass"; fi

echo "-- pre-commit: plaintext env files are blocked, only *.example / *.sample pass"
mkdir -p sub
for f in .env .env.op .env.production .env.local sub/.env .env.test.local; do
  echo "A=1" >"$f"
  git add -f "$f"
  err=$(git commit -m "chore: env" 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then ok "blocked: $f"; else bad "blocked: $f"; fi
  git rm -q --cached "$f"
  rm -f "$f"
done
assert_contains "block message names the rule" "$err" "plaintext .env files must not be committed"
assert_contains "block message suggests op run" "$err" "op run --env-file=op.refs"
assert_contains "hint uses placeholder vault" "$err" "op://example-vault/example-item/field"
echo "A=" >.env.example
echo "A=" >.env.sample
echo "A=" >.env.local.example
echo "A=op://example-vault/example-item/field" >op.refs
git add -f .env.example .env.sample .env.local.example op.refs
if git commit -q -m "chore: env templates" >/dev/null 2>&1; then ok "*.example, *.sample and op.refs allowed"; else bad "templates allowed" "$(git commit -m x 2>&1)"; fi
assert_eq "global ignore hides .env" ".env" "$(
  cd "$T/work/proj" && echo A=1 >.env && git check-ignore .env
  rm -f .env
)"
assert_eq "global ignore hides .env.production" ".env.production" "$(
  echo A=1 >.env.production && git check-ignore .env.production
  rm -f .env.production
)"
assert_eq ".env.example not ignored" "" "$(git check-ignore .env.example)"
assert_eq "op.refs not ignored" "" "$(git check-ignore op.refs)"

echo "-- pre-commit: secrets (fake tokens built at runtime)"
a=AK
b=IA
aws="${a}${b}$(printf 'ABCDEFGHIJKLMNOP')"
gh_tok="gh""p_$(printf 'a1B2%.0s' 1 2 3 4 5 6 7 8 9)"
pk="-----BEGIN ""RSA PRIVATE KEY-----"
slack="xo""xb-$(printf '1234567890')-abcdefghij"
try_secret() { # try_secret NAME CONTENT
  printf '%s\n' "$2" >secret.txt
  git add secret.txt
  err=$(git commit -m "chore: s" 2>&1)
  rc=$?
  git reset -q
  rm -f secret.txt
  if [ $rc -ne 0 ]; then
    ok "blocked: $1"
    case $err in *"$2"*) bad "message leaks the secret for $1" ;; esac
  else bad "blocked: $1" "$err"; fi
}
try_secret "AWS access key" "key = $aws"
try_secret "GitHub token" "token=$gh_tok"
try_secret "private key block" "$pk"
try_secret "Slack token" "$slack"
try_secret "generic secret assignment" "API_SECRET = \"$(printf 'Zz9%.0s' 1 2 3 4 5 6 7 8)\""
printf 'token = "op://example-vault/example-item/field"\n' >ref.txt
git add ref.txt
if git commit -q -m "chore: op ref" >/dev/null 2>&1; then ok "op:// placeholder allowed"; else bad "op:// placeholder allowed"; fi
printf 'x = %s # secret-scan:allow\n' "$aws" >allow.txt
git add allow.txt
if git commit -q -m "chore: allow" >/dev/null 2>&1; then ok "inline secret-scan:allow honoured"; else bad "inline allow"; fi
printf 'key = %s\n' "$aws" >s2.txt
git add s2.txt
if git commit -q --no-verify -m "chore: forced" >/dev/null 2>&1; then ok "--no-verify bypasses secret scan"; else bad "--no-verify secret"; fi

echo "-- pre-commit: large files"
head -c 3000 /dev/zero | tr '\0' 'x' >big.bin
git add big.bin
err=$(GIT_MAX_FILE_BYTES=1000 git commit -m "chore: big" 2>&1)
rc=$?
if [ $rc -ne 0 ]; then ok "oversized file blocked"; else bad "oversized file blocked"; fi
assert_contains "size message" "$err" "exceeds limit"
git reset -q
rm big.bin
printf '{"devDependencies":{"example-dep":"^3.0.0"}}\n' >package.json
git add package.json
git commit -q -m "chore: pkg" >/dev/null 2>&1 && ok "no vendor-specific rules: any dependency is fine" || bad "no vendor rules"

echo "-- pre-push: branch policy and main protection"
push() { git push "$@" >"$T/push.out" 2>&1; }
git checkout -q -b feat/12-good-name 2>/dev/null
if push -u origin feat/12-good-name; then ok "push feat/12-good-name allowed"; else bad "good branch push" "$(cat "$T/push.out")"; fi
git checkout -q -b Bad_Name 2>/dev/null
if push origin Bad_Name; then bad "bad branch name blocked"; else ok "bad branch name blocked"; fi
assert_contains "policy message" "$(cat "$T/push.out")" "branch name must match"
for good in docs/readme fix/9-x chore/a-b-c; do
  git branch -q "$good" 2>/dev/null
  if push origin "$good"; then ok "allowed: $good"; else bad "allowed: $good" "$(cat "$T/push.out")"; fi
done
for badn in feature/x fix/UPPER fix/-lead wip hotfix/1; do
  git branch -q "$badn" 2>/dev/null
  if push origin "$badn"; then bad "blocked: $badn"; else ok "blocked: $badn"; fi
done
git checkout -q main
commit_file . m.txt m "feat: m"
if push origin main; then bad "direct push to main blocked"; else ok "direct push to main blocked"; fi
assert_contains "main message" "$(cat "$T/push.out")" "direct pushes to main"
if GIT_ALLOW_MAIN_PUSH=1 push origin main; then ok "GIT_ALLOW_MAIN_PUSH=1 allows main"; else bad "escape hatch" "$(cat "$T/push.out")"; fi
git reset -q --hard HEAD~1
commit_file . m2.txt m2 "feat: m2"
if GIT_ALLOW_MAIN_PUSH=1 push --force origin main; then bad "force-push main blocked even with escape hatch"; else ok "force-push main blocked even with escape hatch"; fi
assert_contains "force message" "$(cat "$T/push.out")" "force-push"
if push --no-verify --force origin main; then ok "--no-verify is the only way around"; else bad "--no-verify push" "$(cat "$T/push.out")"; fi
if GIT_ALLOW_MAIN_PUSH=1 push origin :main; then bad "deleting main blocked"; else ok "deleting main blocked"; fi
if push origin :docs/readme; then ok "deleting a bad/ok branch allowed"; else bad "branch deletion" "$(cat "$T/push.out")"; fi
git tag v1.0.0
if push origin v1.0.0; then ok "tag push not subject to branch policy"; else bad "tag push" "$(cat "$T/push.out")"; fi

echo "-- chaining to the repo's own hooks"
git checkout -q -b fix/chain 2>/dev/null
hd=.git/hooks
printf '#!/bin/sh\necho ran >> "%s/chain.log"\nexit 0\n' "$T" >$hd/pre-commit
printf '#!/bin/sh\necho "$1" >> "%s/chain.log"\n' "$T" >$hd/commit-msg
printf '#!/bin/sh\ncat > "%s/prepush.stdin"\nexit 0\n' "$T" >$hd/pre-push
printf '#!/bin/sh\necho "post-rewrite-ran" >> "%s/chain.log"\n' "$T" >$hd/post-rewrite
chmod +x $hd/pre-commit $hd/commit-msg $hd/pre-push $hd/post-rewrite
echo c >c.txt
git add c.txt
git commit -q -m "fix: chained" >/dev/null 2>&1
assert_contains "repo pre-commit ran" "$(cat "$T/chain.log")" ran
assert_contains "repo commit-msg ran with msg file" "$(cat "$T/chain.log")" COMMIT_EDITMSG
push -u origin fix/chain
assert_contains "repo pre-push received stdin" "$(cat "$T/prepush.stdin")" "refs/heads/fix/chain"
printf '#!/bin/sh\necho blocked-by-repo >&2\nexit 1\n' >$hd/pre-commit
echo d >d.txt
git add d.txt
if git commit -q -m "fix: blocked by repo hook" >/dev/null 2>&1; then bad "repo hook failure propagates"; else ok "repo hook failure propagates"; fi
printf '#!/bin/sh\nexit 0\n' >$hd/pre-commit
git commit -q -m "fix: d" >/dev/null 2>&1
git commit -q --amend -m "fix: d2" >/dev/null 2>&1
git rebase -q HEAD~1 >/dev/null 2>&1
printf '#!/bin/sh\nexit 1\n' >$hd/pre-push
echo e >e.txt
git add e.txt
git commit -q -m "fix: e" >/dev/null 2>&1
if push origin fix/chain; then bad "repo pre-push failure propagates"; else ok "repo pre-push failure propagates"; fi
chmod -x $hd/pre-push
if push origin fix/chain; then ok "non-executable repo hook ignored"; else bad "non-exec hook" "$(cat "$T/push.out")"; fi
git commit -q --allow-empty -m "fix: pr" >/dev/null 2>&1
(git rebase -q --force-rebase HEAD~1 >/dev/null 2>&1)
assert_contains "passthrough hook (post-rewrite) chained" "$(cat "$T/chain.log")" post-rewrite-ran

echo "-- exempt origin: no global checks, repo hooks still run"
XR=$(mk_remote legacy acme-corp)
clone_to "$XR" "$T/work/fs"
cd "$T/work/fs" || exit 1
printf '#!/bin/sh\necho ex >> "%s/exempt.log"\n' "$T" >.git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
printf 'k = %s\n' "$aws" >s.txt
echo A=1 >.env
git add -f s.txt .env
if git commit -q -m "whatever message" >/dev/null 2>&1; then ok "exempt: bad message, secret and .env all pass"; else bad "exempt commit" "$(git commit -m x 2>&1)"; fi
assert_contains "exempt: repo's own pre-commit still ran" "$(cat "$T/exempt.log")" ex
git checkout -q -b feature/0123-own-style 2>/dev/null
if push -u origin feature/0123-own-style; then ok "exempt: feature/NNNN-slug push allowed"; else bad "exempt push" "$(cat "$T/push.out")"; fi
git checkout -q main
if push origin main; then ok "exempt: main push not guarded"; else bad "exempt main push" "$(cat "$T/push.out")"; fi
git config hooks.exempt false
git commit -q --allow-empty -m "x" >/dev/null 2>&1 && bad "hooks.exempt=false forces enforcement" || ok "hooks.exempt=false forces enforcement"
git config --unset hooks.exempt
GIT_HOOKS_EXEMPT=1 git commit -q --allow-empty -m "x" >/dev/null 2>&1 && ok "GIT_HOOKS_EXEMPT=1 env exemption" || bad "env exemption"
cd "$T/work/proj" || exit 1

echo "-- prepare-commit-msg: issue footer (opt-in)"
git checkout -q -b feat/42-footer 2>/dev/null
git commit -q --allow-empty -m "feat: no footer by default" >/dev/null 2>&1
assert_not_contains "footer off by default" "$(git log -1 --format=%B)" "Refs:"
git config hooks.issueFooter true
git commit -q --allow-empty -m "feat: with footer" >/dev/null 2>&1
assert_contains "footer added" "$(git log -1 --format=%B)" "Refs: #42"
git commit -q --allow-empty -m "feat: explicit #42 mention" >/dev/null 2>&1
assert_eq "no duplicate when already referenced" 0 "$(git log -1 --format=%B | grep -c 'Refs:')"
git config --unset hooks.issueFooter

echo "-- post-commit kicks git-sync in the background, throttled"
unset GIT_SYNC_DISABLE
mkdir -p "$T/stub"
rm -f .git/git-sync.kick
printf '#!/bin/sh\necho "$@" >> "%s/kick.log"\nsleep 2\necho done >> "%s/kick.done"\n' "$T" "$T" >"$T/stub/git-sync"
chmod +x "$T/stub/git-sync"
GIT_SYNC_DISABLE=1 git checkout -q -b feat/99-kick 2>/dev/null
rm -f .git/git-sync.kick
start=$(date +%s)
PATH="$T/stub:$PATH" git commit -q --allow-empty -m "feat: kick" >/dev/null 2>&1
elapsed=$(($(date +%s) - start))
[ $elapsed -lt 2 ] && ok "commit not blocked by background sync (${elapsed}s)" || bad "commit blocked by sync (${elapsed}s)"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$T/kick.log" ] && break
  sleep 0.3
done
assert_contains "git-sync invoked with --hook --quiet" "$(cat "$T/kick.log" 2>/dev/null)" "--hook --quiet"
assert_no_file "kick returned before sync finished" "$T/kick.done"
PATH="$T/stub:$PATH" git commit -q --allow-empty -m "feat: kick2" >/dev/null 2>&1
sleep 0.5
assert_eq "second commit within 5 min does not re-kick" 1 "$(wc -l <"$T/kick.log" | tr -d ' ')"
rm -f "$T/kick.log"
GIT_SYNC_DISABLE=1 git checkout -q fix/chain 2>/dev/null
rm -f .git/git-sync.kick
PATH="$T/stub:$PATH" git checkout -q feat/99-kick
sleep 0.8
assert_contains "post-checkout kicks too" "$(cat "$T/kick.log" 2>/dev/null)" "--hook"
rm -f "$T/kick.log" .git/git-sync.kick
PATH="$T/stub:$PATH" GIT_SYNC_DISABLE=1 git commit -q --allow-empty -m "feat: disabled" >/dev/null 2>&1
sleep 0.5
assert_no_file "GIT_SYNC_DISABLE=1 prevents kick" "$T/kick.log"
cd "$T/work/fs" && rm -f .git/git-sync.kick && PATH="$T/stub:$PATH" git commit -q --allow-empty -m "anything" >/dev/null 2>&1
sleep 0.5
assert_no_file "exempt repo never kicks sync" "$T/kick.log"

summary
