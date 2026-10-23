#!/usr/bin/env bash
# git-sync behaviour tests. No bootstrap here: git-sync is exercised directly.
. "$(dirname "$0")/lib.sh"
t_init
GS=$ROOT/bin/git-sync

state_of() { jq_get ".repos[0].branches[] | select(.name==\"$1\") | .state" "$OUT"; }
new_pair() { # new_pair NAME -> sets REMOTE, LOCAL (clone) and OTHER (second clone)
  REMOTE=$(mk_remote "$1")
  LOCAL=$T/work/$1
  OTHER=$T/work/$1-other
  clone_to "$REMOTE" "$LOCAL"
  clone_to "$REMOTE" "$OTHER"
}

echo "-- usage and exit codes"
run "unknown flag is usage error" 64 "$GS" --bogus
run "outside a repo is usage error" 64 bash -c "cd '$T' && '$GS'"
out=$("$GS" --help)
assert_contains "help has EXIT CODES section" "$out" "EXIT CODES"
json_valid "help --json" "$("$GS" --help --json)"

echo "-- fast-forward, checked-out and other branch, clean tree"
new_pair ff
(
  cd "$LOCAL" && git checkout -q -b feat/other && git push -q -u origin feat/other 2>/dev/null
  git checkout -q main
)
commit_file "$OTHER" a.txt a "feat: a"
push_from "$OTHER" main
(cd "$OTHER" && git fetch -q && git checkout -q feat/other && echo b >b.txt && git add b.txt && git -c core.hooksPath=/dev/null commit -q -m "feat: b") && push_from "$OTHER" feat/other
before=$(git -C "$LOCAL" rev-parse main)
run "dry-run succeeds" 0 "$GS" --repo "$LOCAL" --dry-run --json
assert_eq "dry-run changed nothing" "$before" "$(git -C "$LOCAL" rev-parse main)"
run "sync ff" 0 "$GS" --repo "$LOCAL" --json
json_valid "sync json" "$OUT"
assert_eq "checked-out main fast-forwarded" "$(git -C "$REMOTE" rev-parse main)" "$(git -C "$LOCAL" rev-parse main)"
assert_eq "other branch fast-forwarded" "$(git -C "$REMOTE" rev-parse feat/other)" "$(git -C "$LOCAL" rev-parse feat/other)"
assert_eq "main state" fast-forwarded "$(state_of main)"
assert_eq "working tree updated" a "$(cat "$LOCAL/a.txt")"
run "second sync is a no-op" 0 "$GS" --repo "$LOCAL" --json
assert_eq "main now up-to-date" up-to-date "$(state_of main)"
assert_eq "schema field" git-sync/v1 "$(jq_get .schema "$OUT")"
assert_eq "summary.repos" 1 "$(jq_get .summary.repos "$OUT")"

echo "-- dirty working tree is skipped"
new_pair dirty
commit_file "$OTHER" d.txt d "feat: d"
push_from "$OTHER" main
echo local-change >>"$LOCAL/base.txt"
before=$(git -C "$LOCAL" rev-parse HEAD)
run "dirty behind -> attention" 2 "$GS" --repo "$LOCAL" --json
assert_eq "dirty state" behind-skipped-dirty "$(state_of main)"
assert_eq "HEAD unchanged" "$before" "$(git -C "$LOCAL" rev-parse HEAD)"
assert_contains "local edit preserved" "$(cat "$LOCAL/base.txt")" local-change

echo "-- merge in progress counts as dirty"
new_pair opip
commit_file "$OTHER" o.txt o "feat: o"
push_from "$OTHER" main
touch "$LOCAL/.git/MERGE_HEAD"
run "operation in progress -> attention" 2 "$GS" --repo "$LOCAL" --json
assert_contains "reason mentions MERGE_HEAD" "$(jq_get '.repos[0].branches[0].reason' "$OUT")" MERGE_HEAD
rm -f "$LOCAL/.git/MERGE_HEAD"

echo "-- diverged and ahead"
new_pair div
commit_file "$OTHER" r.txt r "feat: remote"
push_from "$OTHER" main
commit_file "$LOCAL" l.txt l "feat: local"
before=$(git -C "$LOCAL" rev-parse HEAD)
run "diverged -> attention" 2 "$GS" --repo "$LOCAL" --json
assert_eq "diverged state" diverged "$(state_of main)"
assert_eq "diverged untouched" "$before" "$(git -C "$LOCAL" rev-parse HEAD)"
new_pair ahead
commit_file "$LOCAL" l.txt l "feat: local"
run "ahead is fine" 0 "$GS" --repo "$LOCAL" --json
assert_eq "ahead state" ahead "$(state_of main)"
assert_eq "ahead count" 1 "$(jq_get '.repos[0].branches[0].ahead' "$OUT")"

echo "-- no upstream, human output"
new_pair noup
(cd "$LOCAL" && git branch scratch)
run "no-upstream branch" 0 "$GS" --repo "$LOCAL" --json
assert_eq "no-upstream state" no-upstream "$(state_of scratch)"
run "human summary" 0 "$GS" --repo "$LOCAL"
assert_contains "human mentions summary" "$OUT" "git-sync: 1 repo(s)"
run "quiet prints nothing" 0 "$GS" --repo "$LOCAL" --quiet
assert_eq "quiet stdout empty" "" "$OUT"

echo "-- branch checked out in another worktree is never touched"
new_pair wt
(cd "$LOCAL" && git checkout -q -b feat/wt && git push -q -u origin feat/wt 2>/dev/null && git checkout -q main && git worktree add -q "$T/worktrees-wt" feat/wt)
(cd "$OTHER" && git fetch -q && git checkout -q -b feat/wt origin/feat/wt && echo w >w.txt && git add w.txt && git -c core.hooksPath=/dev/null commit -q -m "feat: w" && git -c core.hooksPath=/dev/null push -q origin feat/wt)
before=$(git -C "$LOCAL" rev-parse feat/wt)
run "worktree branch -> attention" 2 "$GS" --repo "$LOCAL" --json
assert_eq "worktree state" behind-skipped-worktree "$(state_of feat/wt)"
assert_eq "worktree branch untouched" "$before" "$(git -C "$LOCAL" rev-parse feat/wt)"

echo "-- gone branches: report, then prune with bundle backup"
new_pair gone
(cd "$LOCAL" && git checkout -q -b feat/merged && echo m >m.txt && git add m.txt && git -c core.hooksPath=/dev/null commit -q -m "feat: m" && git push -q -u origin feat/merged 2>/dev/null &&
  git checkout -q -b feat/unmerged && echo u >u.txt && git add u.txt && git -c core.hooksPath=/dev/null commit -q -m "feat: u" && git push -q -u origin feat/unmerged 2>/dev/null && git checkout -q main)
# remote: merge feat/merged into main (ff), then delete both remote branches
(
  cd "$OTHER" && git fetch -q && git checkout -q main && git pull -q --ff-only 2>/dev/null
  git merge -q --ff-only origin/feat/merged && git -c core.hooksPath=/dev/null push -q origin main && git push -q origin :feat/merged :feat/unmerged 2>/dev/null
)
run "gone reported without prune" 0 "$GS" --repo "$LOCAL" --json
assert_eq "gone state" gone "$(state_of feat/merged)"
assert_eq "still exists" yes "$(git -C "$LOCAL" rev-parse -q --verify refs/heads/feat/merged >/dev/null && echo yes)"
run "prune-merged" 0 "$GS" --repo "$LOCAL" --prune-merged --json
PRUNE_OUT=$OUT
json_valid "prune json" "$OUT"
assert_eq "merged pruned state" pruned "$(state_of feat/merged)"
assert_eq "merged branch deleted" no "$(git -C "$LOCAL" rev-parse -q --verify refs/heads/feat/merged >/dev/null && echo yes || echo no)"
assert_eq "unmerged branch kept" yes "$(git -C "$LOCAL" rev-parse -q --verify refs/heads/feat/unmerged >/dev/null && echo yes)"
assert_eq "unmerged still gone" gone "$(state_of feat/unmerged)"
bundle=$(ls "$GIT_SYNC_BACKUP_DIR"/git-sync-pruned-*.bundle 2>/dev/null | head -n 1)
assert_file "bundle written" "$bundle"
run "bundle verifies" 0 git -C "$LOCAL" bundle verify "$bundle"
assert_contains "bundle contains pruned tip" "$(git -C "$LOCAL" bundle list-heads "$bundle")" refs/heads/feat/merged
assert_eq "json backup path" "$bundle" "$(jq_get '.repos[0].branches[] | select(.name=="feat/merged") | .backup' "$PRUNE_OUT")"

echo "-- squash-merged branch needs --prune-squashed"
new_pair squash
(cd "$LOCAL" && git checkout -q -b feat/sq && echo s1 >s.txt && git add s.txt && git -c core.hooksPath=/dev/null commit -q -m "feat: s1" && echo s2 >>s.txt && git -c core.hooksPath=/dev/null commit -q -am "feat: s2" && git push -q -u origin feat/sq 2>/dev/null && git checkout -q main)
(cd "$OTHER" && git fetch -q && git checkout -q main && git merge -q --squash origin/feat/sq >/dev/null && git -c core.hooksPath=/dev/null commit -q -m "feat: sq (#1)" && git -c core.hooksPath=/dev/null push -q origin main && git push -q origin :feat/sq 2>/dev/null)
run "prune-merged keeps squash branch" 0 "$GS" --repo "$LOCAL" --prune-merged --json
assert_eq "squash branch kept" gone "$(state_of feat/sq)"
run "prune-squashed removes it" 0 "$GS" --repo "$LOCAL" --prune-squashed --json
assert_eq "squash branch pruned" pruned "$(state_of feat/sq)"

echo "-- exempt origin is skipped entirely (nothing is exempt by default)"
REMOTE=$(mk_remote legacy acme-corp)
LOCAL=$T/work/fs
OTHER=$T/work/fs-other
clone_to "$REMOTE" "$LOCAL"
clone_to "$REMOTE" "$OTHER"
commit_file "$OTHER" x.txt x "feat: x"
push_from "$OTHER" main
before=$(git -C "$LOCAL" rev-parse HEAD)
run "default: no exemption" 0 "$GS" --repo "$LOCAL" --dry-run --no-fetch --json
assert_eq "acme-corp repo is NOT exempt by default" ok "$(jq_get '.repos[0].status' "$OUT")"
git config --global --add hooks.exemptOrigins '*[:/]acme-corp/*' # sandbox HOME only
run "exempt repo" 0 "$GS" --repo "$LOCAL" --json
assert_eq "status exempt" exempt "$(jq_get '.repos[0].status' "$OUT")"
assert_eq "exempt flag" true "$(jq_get '.repos[0].exempt' "$OUT")"
assert_eq "exempt repo untouched" "$before" "$(git -C "$LOCAL" rev-parse HEAD)"
assert_eq "exempt repo not even fetched" "$before" "$(git -C "$LOCAL" rev-parse origin/main)"
git config --global --unset-all hooks.exemptOrigins
run "repo-local pattern replaces nothing, adds nothing" 0 "$GS" --repo "$LOCAL" --json
assert_eq "no longer exempt once the pattern is gone" ok "$(jq_get '.repos[0].status' "$OUT")"
git -C "$LOCAL" config hooks.exempt true
run "hooks.exempt=true per repo" 0 "$GS" --repo "$LOCAL" --json
assert_eq "per-repo exempt" exempt "$(jq_get '.repos[0].status' "$OUT")"

echo "-- fetch failure -> exit 3"
new_pair neterr
git -C "$LOCAL" remote set-url origin "$T/remotes/does-not-exist.git"
run "unreachable remote" 3 "$GS" --repo "$LOCAL" --json --timeout 10
json_valid "error json" "$OUT"
assert_eq "fetch ok=false" false "$(jq_get '.repos[0].fetch.ok' "$OUT")"
assert_eq "errors[] populated" 1 "$(jq_get '.errors|length' "$OUT")"

echo "-- --all uses the manifest, --root scans a directory; sync=no and exempt origins win"
git config --global --add hooks.exemptOrigins '*[:/]acme-corp/*'
mkdir -p "$HOME/code"
R1=$(mk_remote a)
R2=$(mk_remote b)
R3=$(mk_remote c acme-corp)
clone_to "$R1" "$HOME/code/a"
clone_to "$R2" "$HOME/code/b"
clone_to "$R3" "$HOME/code/c"
printf 'o/a ~/code/a x yes\no/b ~/code/b x no\no/c ~/code/c x yes\no/gone ~/code/gone x yes\n' >"$T/manifest.txt"
run "--all" 0 "$GS" --all --json --manifest "$T/manifest.txt"
assert_eq "manifest sync=yes repos visited (b skipped, missing dir ignored)" 2 "$(jq_get '.repos|length' "$OUT")"
assert_eq "a ok" ok "$(jq_get '.repos[] | select(.name=="a") | .status' "$OUT")"
assert_eq "c exempt (origin wins)" exempt "$(jq_get '.repos[] | select(.name=="c") | .status' "$OUT")"
run "--root" 0 "$GS" --root "$HOME/code" --json --manifest "$T/manifest.txt"
assert_eq "three repos under root" 3 "$(jq_get '.repos|length' "$OUT")"
assert_eq "b disabled by manifest sync=no" disabled "$(jq_get '.repos[] | select(.name=="b") | .status' "$OUT")"
run "--all without any manifest is a usage error" 64 "$GS" --all
assert_contains "error points at the example" "$ERR" "repos.example.txt"
mkdir -p "$XDG_CONFIG_HOME/dotfiles"
cp "$T/manifest.txt" "$XDG_CONFIG_HOME/dotfiles/repos.txt"
run "--all reads the default manifest in XDG_CONFIG_HOME" 0 "$GS" --all --json
assert_eq "default manifest used" 2 "$(jq_get '.repos|length' "$OUT")"
run "--root must exist" 64 "$GS" --root "$T/nope"
assert_eq "git-sync version from VERSION file" "git-sync $(awk '{print $1; exit}' "$ROOT/VERSION")" "$("$GS" --version)"

echo "-- hook mode: silent, throttled, never updates the checked-out branch"
new_pair hook
commit_file "$OTHER" h.txt h "feat: h"
push_from "$OTHER" main
before=$(git -C "$LOCAL" rev-parse HEAD)
run "hook run" 0 "$GS" --hook --quiet --repo "$LOCAL"
run "hook run from inside repo" 0 bash -c "cd '$LOCAL' && '$GS' --hook"
assert_eq "hook mode printed nothing" "" "$OUT"
assert_eq "checked-out branch untouched by hook" "$before" "$(git -C "$LOCAL" rev-parse HEAD)"
assert_eq "but remote refs fetched" "$(git -C "$REMOTE" rev-parse main)" "$(git -C "$LOCAL" rev-parse origin/main)"
assert_file "throttle stamp written" "$LOCAL/.git/git-sync.last"
commit_file "$OTHER" h2.txt h2 "feat: h2"
push_from "$OTHER" main
run "throttled hook run" 0 bash -c "cd '$LOCAL' && '$GS' --hook"
assert_eq "no second fetch inside 5 min" "no" "$([ "$(git -C "$LOCAL" rev-parse origin/main)" = "$(git -C "$REMOTE" rev-parse main)" ] && echo yes || echo no)"
run "manual sync still works" 0 "$GS" --repo "$LOCAL" --json
assert_eq "manual sync fast-forwards" "$(git -C "$REMOTE" rev-parse main)" "$(git -C "$LOCAL" rev-parse main)"

echo "-- log file written"
assert_file "log exists" "$GIT_SYNC_LOG"

summary
