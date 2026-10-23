#!/usr/bin/env bash
# bootstrap.sh tests: idempotency, backups, dry-run, --check, overlay, layers,
# uninstall, signing, launchd, manifest. Every scenario gets its own sandbox HOME.
. "$(dirname "$0")/lib.sh"
t_init
BS=$ROOT/bootstrap.sh
VER=$(awk '{print $1; exit}' "$ROOT/VERSION")
G() { (cd / && git config "$@"); }

echo "-- version comes from the VERSION file"
assert_eq "bootstrap --version" "bootstrap.sh $VER" "$("$BS" --version)"
assert_contains "VERSION looks like semver" "$VER" "."

echo "-- fresh machine: --check fails, --dry-run changes nothing"
newhome fresh
before=$(snapshot "$HOME")
run "check on empty HOME" 2 "$BS" --check
assert_contains "check reports missing links" "$OUT" "[missing]"
assert_eq "check wrote nothing" "$before" "$(snapshot "$HOME")"
run "dry-run" 0 "$BS" --dry-run --name Test --email test@example.com
assert_eq "dry-run wrote nothing" "$before" "$(snapshot "$HOME")"
assert_contains "dry-run says would-change" "$OUT" "would-change"

echo "-- pre-existing real files are backed up, not lost"
mkdir -p "$HOME/.config/git"
printf 'precious-ignore\n' >"$HOME/.config/git/ignore"
ln -s /nonexistent "$HOME/.config/git/attributes"
printf '[user]\n\tname = Old Name\n\temail = old@example.com\n' >"$HOME/.gitconfig"
run "apply" 0 "$BS" --json
json_valid "apply json" "$OUT"
assert_eq "ignore is now a symlink" "$ROOT/git/ignore" "$(readlink "$HOME/.config/git/ignore")"
bk=$(ls -d "$HOME"/.local/state/dotfiles/backup-* 2>/dev/null | head -n 1)
assert_file "backup dir created" "$bk"
assert_eq "backup keeps original content" "precious-ignore" "$(cat "$bk"/*__ignore 2>/dev/null)"
assert_eq "wrong symlink replaced" "$ROOT/git/attributes" "$(readlink "$HOME/.config/git/attributes")"
for pair in config presets hooks.inc hooks; do
  assert_eq "$pair linked" "$ROOT/git/$pair" "$(readlink "$HOME/.config/git/$pair")"
done
assert_eq "git-sync linked into ~/.local/bin" "$ROOT/bin/git-sync" "$(readlink "$HOME/.local/bin/git-sync")"
OV=$HOME/.config/dotfiles/config
assert_file "overlay created" "$OV"
assert_contains "overlay is the commented template" "$(cat "$OV")" "Your personal dotfiles overlay"
assert_eq "identity carried over from old gitconfig" "Old Name" "$(git config --file "$OV" user.name)"
assert_eq "email carried over" "old@example.com" "$(git config --file "$OV" user.email)"
assert_eq "effective hooksPath" "$HOME/.config/git/hooks" "$(G --type=path core.hooksPath)"
assert_eq "effective pull.ff" only "$(G pull.ff)"
assert_eq "no profile set by default" "" "$(G dotfiles.profile)"
assert_eq "no exempt origins by default" "" "$(G --get-all hooks.exemptOrigins)"
assert_eq "no credential helper imposed" "" "$(G --get-all credential.https://github.com.helper)"
assert_eq "signing not forced" "" "$(G commit.gpgsign)"

echo "-- idempotency and overlay is never overwritten"
tree1=$(snapshot "$HOME")
run "second apply" 0 "$BS" --json
json_valid "second apply json" "$OUT"
assert_eq "nothing changed on second run" 0 "$(jq_get '[.actions[]|select(.status=="changed")]|length' "$OUT")"
assert_eq "tree identical" "$tree1" "$(snapshot "$HOME")"
assert_eq "no second backup dir" 1 "$(ls -d "$HOME"/.local/state/dotfiles/backup-* | wc -l | tr -d ' ')"
printf '[alias]\n\tco = checkout\n' >>"$OV"
run "apply keeps the overlay" 0 "$BS"
assert_eq "overlay customisation survived" checkout "$(git config --file "$OV" alias.co)"
assert_eq "overlay alias effective" checkout "$(G alias.co)"

echo "-- overlay beats the shipped config (included last)"
git config --file "$OV" pull.ff false
assert_eq "overlay overrides presets" false "$(G pull.ff)"
git config --file "$OV" --unset pull.ff
git config --file "$OV" dotfiles.profile strict
assert_eq "profile from overlay" strict "$(G dotfiles.profile)"
git config --file "$OV" --add hooks.exemptOrigins '*github.com/acme-corp/*'
assert_eq "exempt origin from overlay" '*github.com/acme-corp/*' "$(G --get-all hooks.exemptOrigins)"
git config --file "$OV" --unset-all hooks.exemptOrigins

echo "-- overlay follows XDG_CONFIG_HOME (relative include)"
newhome xdg
export XDG_CONFIG_HOME=$T/xdgcfg
"$BS" --no-hooks --name X --email x@example.com >/dev/null
git config --file "$XDG_CONFIG_HOME/dotfiles/config" dotfiles.profile minimal
assert_eq "overlay read from XDG_CONFIG_HOME" minimal "$(G dotfiles.profile)"
assert_eq "presets read from XDG_CONFIG_HOME" only "$(G pull.ff)"
run "xdg check (hooks layer skipped)" 0 "$BS" --check --no-hooks
unset XDG_CONFIG_HOME

echo "-- --check on a healthy machine, and overlay validation"
newhome chk
export PATH="$HOME/.local/bin:$PATH"
"$BS" --name T --email t@example.com >/dev/null
OV=$HOME/.config/dotfiles/config
run "check healthy" 0 "$BS" --check --json
json_valid "check json" "$OUT"
assert_eq "check mode" check "$(jq_get .mode "$OUT")"
assert_eq "check ok" true "$(jq_get .ok "$OUT")"
rm "$HOME/.config/git/hooks"
run "check detects broken link" 2 "$BS" --check --json
assert_eq "check ok=false" false "$(jq_get .ok "$OUT")"
run "re-apply repairs it" 0 "$BS"
run "check healthy again" 0 "$BS" --check
git config --file "$OV" dotfiles.profile paranoid
run "invalid profile detected" 2 "$BS" --check
assert_contains "names the bad profile" "$OUT" "paranoid"
git config --file "$OV" dotfiles.profile strict
git config --file "$OV" hooks.branchName maybe
run "non-boolean switch detected" 2 "$BS" --check
git config --file "$OV" hooks.branchName true
git config --file "$OV" hooks.branchNamePattern '(['
run "invalid regex detected" 2 "$BS" --check
git config --file "$OV" --unset hooks.branchNamePattern
run "valid overlay passes" 0 "$BS" --check
printf '[broken\n' >>"$OV"
run "syntax error detected" 2 "$BS" --check
assert_contains "syntax error reported" "$OUT" "overlay.syntax"
rm "$OV"
run "missing overlay detected" 2 "$BS" --check
assert_contains "missing overlay reported" "$OUT" "[missing]    overlay"

echo "-- no prompts, usage errors, help"
newhome misc
run "CI=1 --yes with closed stdin" 0 env CI=1 "$BS" --yes
run "unknown flag" 64 "$BS" --nope
run "conflicting flags" 64 "$BS" --check --dry-run
run "check+uninstall conflict" 64 "$BS" --check --uninstall
run "uninstall+clone conflict" 64 "$BS" --uninstall --clone-repos
run "bad launchd label" 64 "$BS" --launchd-label 'a b'
json_valid "help --json" "$("$BS" --help --json)"
assert_contains "help documents exit codes" "$("$BS" --help)" "EXIT CODES"
assert_contains "help documents layers" "$("$BS" --help)" "--no-config"
assert_contains "help documents uninstall" "$("$BS" --help)" "--uninstall"

echo "-- layers: hooks-only (--no-config)"
newhome hooksonly
run "hooks-only install" 0 "$BS" --no-config --name T --email t@example.com
assert_file "hooks linked" "$HOME/.config/git/hooks/commit-msg"
assert_eq "hooksPath set" "$HOME/.config/git/hooks" "$(G --type=path core.hooksPath)"
assert_no_file "presets not linked" "$HOME/.config/git/presets"
assert_no_file "ignore not linked" "$HOME/.config/git/ignore"
assert_no_file "attributes not linked" "$HOME/.config/git/attributes"
assert_eq "git presets NOT in effect" "" "$(G pull.ff)"
assert_eq "push.autoSetupRemote NOT in effect" "" "$(G push.autoSetupRemote)"
run "hooks-only check passes with --no-config" 0 "$BS" --check --no-config
mkdir "$T/ho" && (cd "$T/ho" && git init -q && git commit -q --allow-empty -m "bad message" 2>/dev/null) && bad "hooks-only: commit-msg hook active" || ok "hooks-only: commit-msg hook active"
(cd "$T/ho" && git commit -q --allow-empty -m "feat: fine" 2>/dev/null) && ok "hooks-only: conventional message passes" || bad "hooks-only: conventional message passes"

echo "-- layers: config-only (--no-hooks --no-bin)"
newhome configonly
run "config-only install" 0 "$BS" --no-hooks --no-bin --name T --email t@example.com
assert_eq "presets in effect" only "$(G pull.ff)"
assert_eq "autoSetupRemote in effect" true "$(G push.autoSetupRemote)"
assert_eq "no hooksPath" "" "$(G core.hooksPath)"
assert_no_file "hooks not linked" "$HOME/.config/git/hooks"
assert_no_file "hooks.inc not linked" "$HOME/.config/git/hooks.inc"
assert_no_file "bin not linked" "$HOME/.local/bin"
run "config-only check passes with matching flags" 0 "$BS" --check --no-hooks --no-bin
mkdir "$T/co" && (cd "$T/co" && git init -q && git commit -q --allow-empty -m "anything goes" 2>/dev/null) && ok "config-only: no commit checks" || bad "config-only: no commit checks"
run "full check fails on a config-only install" 2 "$BS" --check

echo "-- uninstall: install then uninstall leaves HOME byte-identical"
newhome un
mkdir -p "$HOME/.config/git" "$HOME/.local/bin"
printf 'precious-ignore\n' >"$HOME/.config/git/ignore"
printf 'old-hooks\n' >"$HOME/.config/git/hooks.inc"
ln -s /nonexistent "$HOME/.config/git/attributes"
printf '[user]\n\tname = Old\n\temail = old@example.com\n' >"$HOME/.gitconfig"
before=$(snapshot "$HOME")
run "install into a populated HOME" 0 "$BS"
[ "$before" != "$(snapshot "$HOME")" ] && ok "install changed things" || bad "install changed things"
run "uninstall dry-run" 0 "$BS" --uninstall --dry-run --json
json_valid "uninstall dry-run json" "$OUT"
assert_eq "dry-run mode name" uninstall-dry-run "$(jq_get .mode "$OUT")"
assert_file "dry-run left links" "$HOME/.config/git/config"
run "uninstall" 0 "$BS" --uninstall --json
json_valid "uninstall json" "$OUT"
assert_eq "uninstall mode" uninstall "$(jq_get .mode "$OUT")"
assert_eq "HOME byte-identical after uninstall" "$before" "$(snapshot "$HOME")"
assert_eq "backup restored (content)" "precious-ignore" "$(cat "$HOME/.config/git/ignore")"
assert_eq "dangling link restored" /nonexistent "$(readlink "$HOME/.config/git/attributes")"
run "uninstall is idempotent" 0 "$BS" --uninstall
assert_eq "still identical" "$before" "$(snapshot "$HOME")"
run "uninstall dry-run on clean HOME" 0 "$BS" --uninstall --dry-run
assert_eq "dry-run on clean HOME changes nothing" "$before" "$(snapshot "$HOME")"

echo "-- uninstall on an empty HOME (including repeated installs) leaves nothing behind"
newhome un2
before=$(snapshot "$HOME")
"$BS" --name T --email t@example.com >/dev/null
"$BS" >/dev/null
"$BS" --no-bin >/dev/null
run "uninstall after repeated installs" 0 "$BS" --uninstall
assert_eq "empty HOME restored" "$before" "$(snapshot "$HOME")"

echo "-- uninstall keeps what it must not destroy"
newhome un3
"$BS" --name T --email t@example.com >/dev/null
echo "# my edit" >>"$HOME/.config/dotfiles/config"
rm "$HOME/.local/bin/git-sync"
ln -s /somewhere/else "$HOME/.local/bin/git-sync"
run "uninstall with an edited overlay" 0 "$BS" --uninstall
assert_file "edited overlay kept" "$HOME/.config/dotfiles/config"
assert_contains "kept edit intact" "$(cat "$HOME/.config/dotfiles/config")" "my edit"
assert_eq "foreign link left alone" /somewhere/else "$(readlink "$HOME/.local/bin/git-sync")"
assert_no_file "our links gone" "$HOME/.config/git/config"
assert_contains "reports the kept overlay" "$OUT" "modified; kept"

echo "-- signing toggle (writes the overlay)"
newhome sig
"$BS" --name T --email t@example.com >/dev/null
run "enable without a key fails" 1 "$BS" --enable-signing
run "private key refused" 1 "$BS" --enable-signing --signing-key "key::-----BEGIN ""OPENSSH PRIVATE KEY-----"
assert_eq "signing still off" "" "$(G --type=bool commit.gpgsign)"
run "enable signing" 0 "$BS" --enable-signing --signing-key "key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTests"
assert_eq "gpgsign on" true "$(G --type=bool commit.gpgsign)"
assert_eq "tag signing on" true "$(G --type=bool tag.gpgsign)"
assert_eq "gpg.format ssh" ssh "$(G gpg.format)"
assert_contains "signing key stored" "$(G user.signingkey)" "ssh-ed25519"
assert_eq "no signer program unless asked" "" "$(G gpg.ssh.program)"
printf 'ssh-ed25519 AAAAFakePub test\n' >"$T/k.pub"
run "enable with .pub file and signer" 0 "$BS" --enable-signing --signing-key "$T/k.pub" --signing-program /opt/example/signer
assert_eq "signer stored" /opt/example/signer "$(G gpg.ssh.program)"
run "disable signing" 0 "$BS" --disable-signing
assert_eq "gpgsign off again" false "$(G --type=bool commit.gpgsign)"
run "signing dry-run" 0 "$BS" --enable-signing --signing-key "$T/k.pub" --dry-run
assert_eq "dry-run left signing off" false "$(G --type=bool commit.gpgsign)"

echo "-- launchd (macOS only)"
newhome ld
if [ "$(uname)" = Darwin ]; then
  before=$(snapshot "$HOME")
  run "install-launchd" 0 "$BS" --install-launchd
  plist=$HOME/Library/LaunchAgents/dev.dotfiles.git-sync.plist
  assert_file "plist written with the neutral default label" "$plist"
  assert_not_contains "no unreplaced tokens" "$(cat "$plist")" "@"
  assert_contains "label in plist" "$(cat "$plist")" "<string>dev.dotfiles.git-sync</string>"
  assert_contains "interval 900" "$(cat "$plist")" "<integer>900</integer>"
  assert_contains "points at repo git-sync" "$(cat "$plist")" "$ROOT/bin/git-sync"
  run "uninstall-launchd" 0 "$BS" --uninstall-launchd
  assert_no_file "plist removed" "$plist"
  run "custom label via flag" 0 "$BS" --install-launchd --launchd-label org.example.sync
  assert_file "custom plist" "$HOME/Library/LaunchAgents/org.example.sync.plist"
  DOTFILES_LAUNCHD_LABEL=org.example.env run "custom label via env" 0 "$BS" --install-launchd
  assert_file "env label plist" "$HOME/Library/LaunchAgents/org.example.env.plist"
  run "full uninstall also removes plists it wrote" 0 "$BS" --uninstall
  assert_no_file "Library dirs created for launchd are removed again" "$HOME/Library"
  assert_no_file "env plist removed" "$HOME/Library/LaunchAgents/org.example.env.plist"
else
  run "launchd refused off macOS" 1 "$BS" --install-launchd
fi
assert_no_file "launchd not installed by default" "$HOME/Library/LaunchAgents/dev.dotfiles.git-sync.plist"
assert_not_contains "template filename is neutral" "$(ls "$ROOT/launchd")" "jewell"

echo "-- manifest: lives in the overlay dir, --clone-repos"
newhome mf
CB=$T/remotes/clone
mkdir -p "$CB/owner"
for r in one two; do
  git init -q --bare -b main "$CB/owner/$r.git"
  s=$T/seed-$r
  git init -q -b main "$s"
  (cd "$s" && echo x >x && git add x && git -c core.hooksPath=/dev/null commit -q -m "chore: seed" && git -c core.hooksPath=/dev/null push -q "$CB/owner/$r.git" main)
  rm -rf "$s"
done
run "no manifest is fine" 0 "$BS" --name T --email t@example.com --json
assert_eq "manifest skipped" skipped "$(jq_get '.actions[]|select(.id=="manifest")|.status' "$OUT")"
run "--clone-repos without manifest fails" 1 "$BS" --clone-repos
printf 'owner/one ~/code/one infra yes\nowner/two ~/code/two dev no exempt\n# owner/three ~/code/three dev yes\n' >"$T/m.txt"
run "manifest without --clone-repos only warns" 0 "$BS" --manifest "$T/m.txt" --json
assert_eq "repo listed as absent" false "$(jq_get '.manifest[0].present' "$OUT")"
assert_no_file "nothing cloned" "$HOME/code/one"
DOTFILES_CLONE_BASE="$CB/" run "clone dry-run" 0 "$BS" --manifest "$T/m.txt" --clone-repos --dry-run
assert_no_file "dry-run cloned nothing" "$HOME/code/one"
DOTFILES_CLONE_BASE="$CB/" run "clone-repos" 0 "$BS" --manifest "$T/m.txt" --clone-repos --json
assert_file "cloned one" "$HOME/code/one/x"
assert_file "cloned two" "$HOME/code/two/x"
assert_eq "exempt flag in manifest json" true "$(jq_get '.manifest[1].exempt' "$OUT")"
DOTFILES_CLONE_BASE="$CB/" run "clone-repos idempotent" 0 "$BS" --manifest "$T/m.txt" --clone-repos
cp "$T/m.txt" "$XDG_CONFIG_HOME/dotfiles/repos.txt"
run "default manifest location is read" 0 "$BS" --json
assert_eq "default manifest used" 2 "$(jq_get '.manifest|length' "$OUT")"
printf 'owner/zzz ~/code/zzz dev yes\n' >"$T/m2.txt"
DOTFILES_CLONE_BASE="$CB/nonexistent/" run "clone failure -> exit 1" 1 "$BS" --manifest "$T/m2.txt" --clone-repos
printf 'owner/bad onlytwo\n' >"$T/m3.txt"
run "malformed manifest line flagged by --check" 2 "$BS" --check --manifest "$T/m3.txt"

echo "-- the shipped example manifest parses and is neutral"
ex=$ROOT/manifest/repos.example.txt
assert_file "example manifest exists" "$ex"
assert_no_file "no real manifest is tracked" "$ROOT/manifest/repos.txt"
mf=$(grep -v '^#' "$ex" | grep -v '^$')
assert_contains "uses neutral owner" "$mf" "acme-corp/"
assert_eq "every example line has >= 4 columns and yes|no" 0 "$(printf '%s\n' "$mf" | awk 'NF < 4 || ($4 != "yes" && $4 != "no") { n++ } END { print n + 0 }')"
run "--check accepts the example manifest" 0 "$BS" --check --manifest "$ex"

summary
