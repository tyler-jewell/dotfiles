#!/usr/bin/env bash
# bootstrap.sh - install, check or remove these dotfiles (macOS or Linux).
# Idempotent. Never prompts. Never overwrites a real file without first moving
# it into ~/.local/state/dotfiles/backup-<timestamp>/. Everything it does is
# recorded in a receipt so --uninstall can undo exactly that. See --help.
SELF=$0
while [ -L "$SELF" ]; do
  _d=$(cd -P "$(dirname "$SELF")" && pwd)
  SELF=$(readlink "$SELF")
  case $SELF in /*) ;; *) SELF="$_d/$SELF" ;; esac
done
ROOT=$(cd -P "$(dirname "$SELF")" && pwd)
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh" || {
  echo "bootstrap: cannot load lib/common.sh" >&2
  exit 1
}
VERSION=$(dot_version "$ROOT")

usage_text() {
  cat <<'EOF'
bootstrap.sh - install the dotfiles (git config presets, global hooks, git-sync)

USAGE
  ./bootstrap.sh [options]

MODES
  (default)            apply: link files, create your overlay template, link bin/
  --dry-run, -n        show what apply/uninstall would do; change nothing
  --check              doctor: read-only health report; exit 2 if anything is
                       missing or wrong
  --uninstall          remove exactly what bootstrap linked or created and
                       restore backups; idempotent

LAYERS (default: all three)
  --no-config          skip the git presets (pull.ff=only etc.), global ignore
                       and attributes. Hooks-only install.
  --no-hooks           skip the global hooks and core.hooksPath. Config-only.
  --no-bin             skip the ~/.local/bin links (git-sync, dotfiles-bootstrap)

OPTIONS
  --json               one JSON document on stdout (schema dotfiles-bootstrap/v1)
  --yes, -y            accepted for scripts; bootstrap never prompts anyway
  --name NAME          user.name for your overlay (default: current git value)
  --email EMAIL        user.email for your overlay (default: current git value)
  --clone-repos        clone repos from the manifest that are missing locally
  --manifest FILE      repo manifest (default: ${XDG_CONFIG_HOME:-~/.config}/dotfiles/repos.txt)
  --enable-signing     turn on SSH commit/tag signing in your overlay
  --signing-key VALUE  public key: path to a .pub file or 'key::ssh-ed25519 AAAA...'
                       (default: ~/.ssh/id_ed25519.pub). Never pass a private key.
  --signing-program P  optional gpg.ssh.program (e.g. a password manager's signer)
  --disable-signing    turn signing off again (key is kept)
  --install-launchd    macOS: install the 15-minute `git-sync --all` LaunchAgent
  --uninstall-launchd  remove it
  --launchd-label L    LaunchAgent label (default dev.dotfiles.git-sync, or
                       $DOTFILES_LAUNCHD_LABEL)
  --help [--json]      this text or a machine-readable description
  --version

EXIT CODES
  0   success (or --check found nothing missing)
  1   an action failed
  2   --check found something missing or wrong
  64  usage error

FILES TOUCHED (all under $HOME; originals are moved to the backup dir)
  ~/.config/git/{config,presets,ignore,attributes}  symlinks (config layer)
  ~/.config/git/{hooks,hooks.inc}                   symlinks (hooks layer)
  ~/.config/dotfiles/config                         YOUR overlay: real file,
                                                    created once, never overwritten
  ~/.local/bin/{git-sync,dotfiles-bootstrap}        symlinks (bin layer)
  ~/.local/state/dotfiles/{receipt,backup-<ts>/}    undo information
Only the repo manifest is optional: ~/.config/dotfiles/repos.txt is yours to create.
Requires ~/.local/bin on PATH for `git sync` (bootstrap warns; it never edits
shell rc files). XDG_CONFIG_HOME is honoured, except that core.hooksPath in
git/hooks.inc assumes ~/.config/git.
EOF
}

usage_json() {
  cat <<EOF
{"name":"bootstrap.sh","version":"$VERSION","schema":"dotfiles-bootstrap/v1","interactive":false,
 "modes":["apply","--dry-run","--check","--uninstall"],
 "layers":["--no-config","--no-hooks","--no-bin"],
 "options":["--json","--yes","--name","--email","--clone-repos","--manifest","--enable-signing","--signing-key","--signing-program","--disable-signing","--install-launchd","--uninstall-launchd","--launchd-label","--help","--version"],
 "exit_codes":{"0":"success","1":"action failed","2":"check found problems","64":"usage error"},
 "statuses":["ok","changed","would-change","missing","wrong","warn","error","skipped"]}
EOF
}

DRY=0 CHECK=0 UNINSTALL=0 JSON=0 CLONE=0 SIGN_ON=0 SIGN_OFF=0 LD_ON=0 LD_OFF=0 HELP=0
NO_CONFIG=0 NO_HOOKS=0 NO_BIN=0
OPT_NAME="" OPT_EMAIL="" SIGN_KEY="" SIGN_PROG="" MANIFEST="" MANIFEST_EXPLICIT=0
LABEL=${DOTFILES_LAUNCHD_LABEL:-dev.dotfiles.git-sync}
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run | -n) DRY=1 ;;
    --check) CHECK=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --no-config) NO_CONFIG=1 ;;
    --no-hooks) NO_HOOKS=1 ;;
    --no-bin) NO_BIN=1 ;;
    --json) JSON=1 ;;
    --yes | -y) ;;
    --clone-repos) CLONE=1 ;;
    --enable-signing) SIGN_ON=1 ;;
    --disable-signing) SIGN_OFF=1 ;;
    --install-launchd) LD_ON=1 ;;
    --uninstall-launchd) LD_OFF=1 ;;
    --name | --email | --signing-key | --signing-program | --manifest | --launchd-label)
      [ $# -ge 2 ] || {
        echo "bootstrap: $1 needs a value" >&2
        exit 64
      }
      case $1 in
        --name) OPT_NAME=$2 ;; --email) OPT_EMAIL=$2 ;;
        --signing-key) SIGN_KEY=$2 ;; --signing-program) SIGN_PROG=$2 ;;
        --manifest)
          MANIFEST=$2
          MANIFEST_EXPLICIT=1
          ;;
        --launchd-label) LABEL=$2 ;;
      esac
      shift
      ;;
    -h | --help) HELP=1 ;;
    --version)
      echo "bootstrap.sh $VERSION"
      exit 0
      ;;
    *)
      echo "bootstrap: unknown argument: $1 (try --help)" >&2
      exit 64
      ;;
  esac
  shift
done
if [ $HELP = 1 ]; then
  if [ $JSON = 1 ]; then usage_json; else usage_text; fi
  exit 0
fi
usage_err() {
  echo "bootstrap: $1" >&2
  exit 64
}
[ $SIGN_ON = 1 ] && [ $SIGN_OFF = 1 ] && usage_err "--enable-signing and --disable-signing conflict"
[ $LD_ON = 1 ] && [ $LD_OFF = 1 ] && usage_err "--install-launchd and --uninstall-launchd conflict"
[ $CHECK = 1 ] && [ $DRY = 1 ] && usage_err "--check and --dry-run are separate modes"
[ $CHECK = 1 ] && [ $UNINSTALL = 1 ] && usage_err "--check and --uninstall are separate modes"
if [ $UNINSTALL = 1 ] && [ $((CLONE + SIGN_ON + SIGN_OFF + LD_ON + LD_OFF)) -gt 0 ]; then
  usage_err "--uninstall cannot be combined with --clone-repos, signing or launchd options"
fi
case $LABEL in '' | *[!A-Za-z0-9._-]*) usage_err "--launchd-label may contain only letters, digits, . _ -" ;; esac

# ---------------------------------------------------------------- paths
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
GITDIR=$CONFIG_HOME/git
OVERLAY_DIR=$(dot_config_dir)
OVERLAY=$OVERLAY_DIR/config
[ -n "$MANIFEST" ] || MANIFEST=$(dot_default_manifest)
BINDIR=$HOME/.local/bin
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles
RECEIPT=$STATE/receipt
TS=$(date +%Y%m%dT%H%M%S)
BACKUP_DIR=$STATE/backup-$TS
BACKED_UP=0
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
TAB=$(printf '\t')

# ---------------------------------------------------------------- reporting
ACTIONS_JSON="" PROBLEMS=0 FAILURES=0
rec() { # rec ID STATUS DETAIL
  local id=$1 st=$2 detail=$3
  ACTIONS_JSON="${ACTIONS_JSON:+$ACTIONS_JSON,}{\"id\":$(dot_json_str "$id"),\"status\":\"$st\",\"detail\":$(dot_json_str "$detail")}"
  case $st in missing | wrong) PROBLEMS=$((PROBLEMS + 1)) ;; error)
    FAILURES=$((FAILURES + 1))
    PROBLEMS=$((PROBLEMS + 1))
    ;;
  esac
  [ $JSON = 1 ] || printf '%-12s %-26s %s\n' "[$st]" "$id" "$detail"
}

# ---------------------------------------------------------------- receipt
# One tab-separated line per thing bootstrap created, so --uninstall can undo
# exactly that:  link DEST SRC | backup ORIGINAL BACKUPFILE | file PATH CKSUM | dir PATH
cksum_of() { cksum <"$1" 2>/dev/null | awk '{print $1 ":" $2}'; }
ensure_state() { # create the state dir, recording every directory created
  local d=$STATE missing="" x
  while [ ! -d "$d" ] && [ "$d" != / ] && [ "$d" != . ]; do
    missing="$d
$missing"
    d=$(dirname "$d")
  done
  mkdir -p "$STATE" || return 1
  while IFS= read -r x; do [ -n "$x" ] && printf 'dir\t%s\n' "$x" >>"$RECEIPT"; done <<EOF2
$missing
EOF2
  return 0
}
receipt_add() { # receipt_add KIND A [B]
  local line="$1$TAB$2${3:+$TAB$3}"
  [ -d "$STATE" ] || ensure_state || return 1
  if [ -f "$RECEIPT" ] && grep -Fxq -- "$line" "$RECEIPT" 2>/dev/null; then return 0; fi
  printf '%s\n' "$line" >>"$RECEIPT"
}
receipt_del() { # receipt_del KIND A  (drop entries of KIND for path A)
  [ -f "$RECEIPT" ] || return 0
  awk -F "$TAB" -v k="$1" -v a="$2" '!($1 == k && $2 == a)' "$RECEIPT" >"$RECEIPT.tmp" && mv "$RECEIPT.tmp" "$RECEIPT"
}
mkd() { # mkdir -p that records every directory it had to create
  local d=$1 missing="" x
  while [ ! -d "$d" ] && [ "$d" != / ] && [ "$d" != . ]; do
    missing="$d
$missing"
    d=$(dirname "$d")
  done
  mkdir -p "$1" || return 1
  while IFS= read -r x; do [ -n "$x" ] && receipt_add dir "$x"; done <<EOF
$missing
EOF
  return 0
}

backup() { # move an existing path out of the way and remember where it came from
  local p=$1 flat
  flat=$(printf '%s' "$p" | sed 's#^/##; s#/#__#g')
  mkd "$BACKUP_DIR" && mv "$p" "$BACKUP_DIR/$flat" && receipt_add backup "$p" "$BACKUP_DIR/$flat" &&
    BACKED_UP=$((BACKED_UP + 1))
}

link() { # link ID SRC DEST
  local id=$1 src=$2 dest=$3
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    rec "$id" ok "$dest -> $src"
    return
  fi
  if [ $CHECK = 1 ]; then
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      rec "$id" wrong "$dest is not a link to $src"
    else rec "$id" missing "$dest"; fi
    return
  fi
  if [ $DRY = 1 ]; then
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      rec "$id" would-change "back up $dest, then link -> $src"
    else rec "$id" would-change "link $dest -> $src"; fi
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup "$dest" || {
      rec "$id" error "cannot back up $dest"
      return
    }
  fi
  if mkd "$(dirname "$dest")" && ln -s "$src" "$dest" && receipt_add link "$dest" "$src"; then
    rec "$id" changed "$dest -> $src"
  else rec "$id" error "cannot link $dest"; fi
}

# The links, one list used by apply, check and uninstall: "ID|SRC|DEST|LAYER"
link_list() {
  printf '%s\n' \
    "git.config|$ROOT/git/config|$GITDIR/config|core" \
    "git.presets|$ROOT/git/presets|$GITDIR/presets|config" \
    "git.ignore|$ROOT/git/ignore|$GITDIR/ignore|config" \
    "git.attributes|$ROOT/git/attributes|$GITDIR/attributes|config" \
    "git.hooks.inc|$ROOT/git/hooks.inc|$GITDIR/hooks.inc|hooks" \
    "git.hooks|$ROOT/git/hooks|$GITDIR/hooks|hooks" \
    "bin.git-sync|$ROOT/bin/git-sync|$BINDIR/git-sync|bin" \
    "bin.dotfiles-bootstrap|$ROOT/bootstrap.sh|$BINDIR/dotfiles-bootstrap|bin"
}
layer_on() {
  case $1 in
    config) [ $NO_CONFIG = 0 ] ;;
    hooks) [ $NO_HOOKS = 0 ] ;;
    bin) [ $NO_BIN = 0 ] ;;
    *) return 0 ;;
  esac
}
link_layers() {
  local id src dest layer
  while IFS='|' read -r id src dest layer; do
    layer_on "$layer" && link "$id" "$src" "$dest"
  done <<EOF
$(link_list)
EOF
}

# ---------------------------------------------------------------- sections
# gcfg: effective config as git sees it outside any repo. (`git config --global`
# reads only ~/.gitconfig when that file exists, so it cannot see ~/.config/git.)
gcfg() { (cd / && git config "$@"); }

detect_identity() { # must run BEFORE linking: the old global config may be moved away
  NAME=${OPT_NAME:-$(gcfg --get user.name 2>/dev/null)}
  EMAIL=${OPT_EMAIL:-$(gcfg --get user.email 2>/dev/null)}
}

validate_overlay() { # validate_overlay FILE -> rec results for a user overlay
  local f=$1 k v bad=0 p
  if ! git config --file "$f" --list >/dev/null 2>&1; then
    rec overlay.syntax wrong "$f is not valid git-config syntax"
    return
  fi
  rec overlay.syntax ok "parses"
  v=$(git config --file "$f" --get dotfiles.profile 2>/dev/null)
  case $(dot_lower "$v") in
    '' | minimal | standard | strict) ;;
    *)
      rec overlay.profile wrong "dotfiles.profile='$v' (use minimal, standard or strict)"
      bad=1
      ;;
  esac
  for k in secretScan conventionalCommits branchName protectMain sync issueFooter exempt; do
    if git config --file "$f" --get-all "hooks.$k" >/dev/null 2>&1 &&
      ! git config --file "$f" --type=bool --get-all "hooks.$k" >/dev/null 2>&1; then
      rec "overlay.hooks.$k" wrong "hooks.$k must be true or false"
      bad=1
    fi
  done
  p=$(git config --file "$f" --get hooks.branchNamePattern 2>/dev/null)
  if [ -n "$p" ]; then
    printf '' | grep -E -e "$p" >/dev/null 2>&1
    if [ $? -eq 2 ]; then
      rec overlay.branchNamePattern wrong "hooks.branchNamePattern is not a valid extended regex"
      bad=1
    fi
  fi
  [ $bad = 0 ] && rec overlay.values ok "profile and switches are valid"
}

setup_overlay() {
  local k v
  if [ $CHECK = 1 ]; then
    if [ ! -f "$OVERLAY" ]; then
      rec overlay missing "$OVERLAY (bootstrap creates a commented template)"
      return
    fi
    rec overlay ok "$OVERLAY"
    validate_overlay "$OVERLAY"
    return
  fi
  if [ $DRY = 1 ]; then
    if [ -f "$OVERLAY" ]; then
      rec overlay ok "exists, left untouched ($OVERLAY)"
    else rec overlay would-change "create commented template $OVERLAY"; fi
    return
  fi
  if [ ! -f "$OVERLAY" ]; then
    if mkd "$OVERLAY_DIR" && cp "$ROOT/templates/config.example" "$OVERLAY"; then
      OVERLAY_CREATED=1
      rec overlay changed "created $OVERLAY"
    else
      rec overlay error "cannot create $OVERLAY"
      return
    fi
  else
    rec overlay ok "exists, left untouched ($OVERLAY)"
  fi
  for k in name email; do
    v=$NAME
    [ $k = email ] && v=$EMAIL
    if [ -n "$(git config --file "$OVERLAY" --get "user.$k" 2>/dev/null)" ]; then
      rec "identity.user.$k" ok "already in overlay"
    elif [ -n "$v" ]; then
      git config --file "$OVERLAY" "user.$k" "$v" && rec "identity.user.$k" changed "written to overlay"
    else
      rec "identity.user.$k" warn "unknown; pass --$k or set it in $OVERLAY"
    fi
  done
}

# Record the overlay in the receipt AFTER all automatic edits, so --uninstall can
# tell an untouched file (removed) from one you edited (kept).
seal_overlay() {
  [ "$OVERLAY_CREATED" = 1 ] && [ $CHECK = 0 ] && [ $DRY = 0 ] && [ -f "$OVERLAY" ] || return 0
  receipt_del file "$OVERLAY"
  receipt_add file "$OVERLAY" "$(cksum_of "$OVERLAY")"
}

check_deps() {
  local t
  for t in git gitleaks jq op; do
    if command -v "$t" >/dev/null 2>&1; then
      rec "dep.$t" ok "$(command -v "$t")"
    else
      case $t in
        git) rec dep.git missing "git is required" ;;
        gitleaks) rec dep.gitleaks skipped "optional: adds a larger secret ruleset to pre-commit (built-in scanner is used meanwhile)" ;;
        jq) rec dep.jq skipped "optional: only for reading --json output" ;;
        op) rec dep.op skipped "optional: 1Password CLI, one way to keep secrets as op:// references" ;;
      esac
    fi
  done
}

check_effective() {
  local hp pr v h bad=""
  if [ $NO_HOOKS = 0 ]; then
    hp=$(gcfg --type=path --get core.hooksPath 2>/dev/null)
    if [ -n "$hp" ] && [ "$hp" -ef "$GITDIR/hooks" ]; then
      rec git.hooksPath ok "core.hooksPath -> $hp"
    else rec git.hooksPath wrong "core.hooksPath is '${hp:-unset}', expected $GITDIR/hooks"; fi
    for h in commit-msg pre-commit pre-push post-checkout post-merge post-commit; do
      [ -x "$ROOT/git/hooks/$h" ] || bad="$bad $h"
    done
    if [ -z "$bad" ]; then rec hooks.executable ok "all hooks executable"; else rec hooks.executable wrong "not executable:$bad"; fi
    pr=$(gcfg --get dotfiles.profile 2>/dev/null)
    case $(dot_lower "$pr") in
      '') rec profile ok "standard (default)" ;;
      minimal | standard | strict) rec profile ok "$(dot_lower "$pr")" ;;
      *) rec profile wrong "dotfiles.profile='$pr' is invalid; treated as standard" ;;
    esac
    [ "$CONFIG_HOME" = "$HOME/.config" ] || rec xdg warn "XDG_CONFIG_HOME=$CONFIG_HOME but git/hooks.inc points core.hooksPath at ~/.config/git/hooks"
  fi
  if [ $NO_CONFIG = 0 ]; then
    [ "$(gcfg --get pull.ff 2>/dev/null)" = only ] && rec git.presets ok "pull.ff=only in effect" ||
      rec git.presets wrong "pull.ff is not 'only' (presets not in effect; ~/.gitconfig may override)"
  fi
  [ -f "$HOME/.gitconfig" ] && rec legacy.gitconfig warn "$HOME/.gitconfig exists and overrides ~/.config/git/* where keys overlap (including your overlay)"
  v=$(git --version | sed 's/[^0-9.]//g' | cut -d. -f1,2)
  if [ "$(printf '%s\n2.35\n' "$v" | sort -t. -k1,1n -k2,2n | head -n1)" = 2.35 ]; then
    rec git.version ok "$(git --version)"
  else rec git.version warn "$(git --version); 2.35+ needed (merge.conflictStyle=zdiff3 in the presets)"; fi
  if [ "$(git config --file "$OVERLAY" --type=bool --get commit.gpgsign 2>/dev/null)" = true ]; then
    rec signing ok "enabled (key $(git config --file "$OVERLAY" --get user.signingkey 2>/dev/null | cut -c1-40))"
  else rec signing ok "disabled (bootstrap --enable-signing to turn on)"; fi
  [ -f "$PLIST" ] && rec launchd ok "installed: $PLIST"
}

toggle_signing() {
  local key=$SIGN_KEY
  if [ $SIGN_OFF = 1 ]; then
    if [ $DRY = 1 ]; then
      rec signing would-change "set commit.gpgsign=false in overlay"
      return
    fi
    git config --file "$OVERLAY" commit.gpgsign false && git config --file "$OVERLAY" tag.gpgsign false &&
      rec signing changed "disabled (key kept in overlay)"
    return
  fi
  if [ -z "$key" ]; then
    [ -f "$HOME/.ssh/id_ed25519.pub" ] && key=$HOME/.ssh/id_ed25519.pub
  fi
  if [ -z "$key" ]; then
    rec signing error "no key: pass --signing-key <path-to-.pub | key::ssh-ed25519 AAAA...>"
    return
  fi
  case $key in *"PRIVATE KEY"*)
    rec signing error "refusing a private key; pass the PUBLIC key"
    return
    ;;
  esac
  case $key in
    key::*) ;;
    *)
      key=${key/#\~/$HOME}
      if [ ! -f "$key" ]; then
        rec signing error "key file not found: $key"
        return
      fi
      if head -c 64 "$key" | grep -q 'PRIVATE KEY'; then
        rec signing error "refusing a private key file: $key"
        return
      fi
      ;;
  esac
  if [ $DRY = 1 ]; then
    rec signing would-change "enable SSH signing with ${key}${SIGN_PROG:+ via $SIGN_PROG}"
    return
  fi
  git config --file "$OVERLAY" user.signingkey "$key" &&
    git config --file "$OVERLAY" gpg.format ssh &&
    git config --file "$OVERLAY" commit.gpgsign true &&
    git config --file "$OVERLAY" tag.gpgsign true || {
    rec signing error "cannot write $OVERLAY"
    return
  }
  if [ -n "$SIGN_PROG" ]; then
    git config --file "$OVERLAY" gpg.ssh.program "$SIGN_PROG"
    rec signing changed "enabled; signer $SIGN_PROG"
  else
    rec signing changed "enabled; git will use ssh-keygen + ssh-agent"
  fi
}

launchd_toggle() {
  local uid
  if [ "$(uname)" != Darwin ]; then
    rec launchd error "launchd is macOS only"
    return
  fi
  uid=$(id -u)
  if [ $LD_OFF = 1 ]; then
    if [ $DRY = 1 ]; then
      rec launchd would-change "remove $PLIST"
      return
    fi
    [ "${DOTFILES_SKIP_LAUNCHCTL:-}" = 1 ] || launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1
    rm -f "$PLIST" && receipt_del file "$PLIST" && rec launchd changed "removed $PLIST"
    return
  fi
  if [ $DRY = 1 ]; then
    rec launchd would-change "write $PLIST and load it (every 900s: git-sync --all)"
    return
  fi
  mkd "$(dirname "$PLIST")" && mkd "$HOME/Library/Logs"
  sed -e "s#@GIT_SYNC@#$ROOT/bin/git-sync#g" -e "s#@HOME@#$HOME#g" -e "s#@LABEL@#$LABEL#g" \
    "$ROOT/launchd/dev.dotfiles.git-sync.plist.tmpl" >"$PLIST" || {
    rec launchd error "cannot write $PLIST"
    return
  }
  receipt_del file "$PLIST"
  receipt_add file "$PLIST" "$(cksum_of "$PLIST")"
  if [ "${DOTFILES_SKIP_LAUNCHCTL:-}" = 1 ]; then
    rec launchd changed "wrote $PLIST (launchctl skipped)"
  else
    launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1
    if launchctl bootstrap "gui/$uid" "$PLIST" 2>/dev/null; then
      rec launchd changed "installed and loaded $PLIST"
    else rec launchd error "wrote $PLIST but launchctl bootstrap failed"; fi
  fi
}

MANIFEST_JSON=""
manifest() {
  local owner dest role sync extra p present base n=0
  if [ ! -f "$MANIFEST" ]; then
    if [ $MANIFEST_EXPLICIT = 1 ] || [ $CLONE = 1 ]; then
      rec manifest error "no manifest at $MANIFEST"
    else rec manifest skipped "none at $MANIFEST (optional; see manifest/repos.example.txt)"; fi
    return
  fi
  base=${DOTFILES_CLONE_BASE:-https://github.com/}
  while read -r owner dest role sync extra; do
    case $owner in '' | \#*) continue ;; esac
    n=$((n + 1))
    if [ -z "$dest" ] || [ -z "$role" ] || { [ "$sync" != yes ] && [ "$sync" != no ]; }; then
      rec "manifest.line" wrong "bad entry for '$owner' (need: owner/repo dest role yes|no)"
      continue
    fi
    p=${dest/#\~/$HOME}
    present=false
    [ -e "$p/.git" ] && present=true
    MANIFEST_JSON="${MANIFEST_JSON:+$MANIFEST_JSON,}{\"repo\":$(dot_json_str "$owner"),\"dest\":$(dot_json_str "$p"),\"role\":$(dot_json_str "$role"),\"sync\":$(dot_json_str "$sync"),\"exempt\":$([ "$extra" = exempt ] && echo true || echo false),\"present\":$present}"
    if [ $present = true ]; then
      rec "repo.$owner" ok "$p"
    elif [ $CLONE = 1 ] && [ $CHECK = 0 ]; then
      if [ $DRY = 1 ]; then
        rec "repo.$owner" would-change "clone ${base}${owner}.git -> $p"
      elif mkdir -p "$(dirname "$p")" && git clone --quiet "${base}${owner}.git" "$p" </dev/null 2>/dev/null; then
        rec "repo.$owner" changed "cloned to $p"
      else rec "repo.$owner" error "clone failed ($owner; check network and credentials)"; fi
    else
      rec "repo.$owner" warn "not cloned: $p (run with --clone-repos)${extra:+ [$extra]}"
    fi
  done <"$MANIFEST"
  [ $n -gt 0 ] || rec manifest ok "$MANIFEST has no entries"
}

# ---------------------------------------------------------------- uninstall
do_uninstall() {
  local id src dest layer cur line kind a b NEWREC="" ck dirs="" d
  # 1. links (known list: works even without a receipt)
  while IFS='|' read -r id src dest layer; do
    if [ -L "$dest" ]; then
      cur=$(readlink "$dest")
      if [ "$cur" = "$src" ]; then
        if [ $DRY = 1 ]; then
          rec "$id" would-change "remove link $dest"
        else rm -f "$dest" && rec "$id" changed "removed $dest"; fi
      else rec "$id" skipped "$dest points elsewhere ($cur); left alone"; fi
    elif [ -e "$dest" ]; then
      rec "$id" skipped "$dest is not a link; left alone"
    else rec "$id" ok "not installed"; fi
  done <<EOF
$(link_list)
EOF
  [ -f "$RECEIPT" ] || {
    rec receipt ok "no receipt: nothing else to undo"
    return
  }
  # 2. launchd plist and other created files, then backups, then dirs
  while IFS="$TAB" read -r kind a b; do
    [ "$kind" = file ] || continue
    if [ ! -e "$a" ]; then continue; fi
    ck=$(cksum_of "$a")
    if [ "$ck" = "$b" ]; then
      if [ $DRY = 1 ]; then
        rec "file" would-change "remove $a"
      else
        case $a in */LaunchAgents/*.plist)
          [ "${DOTFILES_SKIP_LAUNCHCTL:-}" = 1 ] || launchctl bootout "gui/$(id -u)/$(basename "$a" .plist)" >/dev/null 2>&1
          ;;
        esac
        rm -f "$a" && rec "file" changed "removed $a"
      fi
    else
      rec "file" skipped "$a was modified; kept"
      NEWREC="$NEWREC$kind$TAB$a$TAB$b
"
    fi
  done <"$RECEIPT"
  while IFS="$TAB" read -r kind a b; do
    [ "$kind" = backup ] || continue
    if [ ! -e "$b" ] && [ ! -L "$b" ]; then continue; fi
    if { [ -e "$a" ] || [ -L "$a" ]; } && ! { [ $DRY = 1 ] && [ -L "$a" ] && [ "$(readlink "$a" | cut -c1-${#ROOT})" = "$ROOT" ]; }; then
      rec backup skipped "$a exists; backup $b kept"
      NEWREC="$NEWREC$kind$TAB$a$TAB$b
"
    elif [ $DRY = 1 ]; then
      rec backup would-change "restore $a from $b"
    else
      mkdir -p "$(dirname "$a")" && mv "$b" "$a" && rec backup changed "restored $a" ||
        rec backup error "cannot restore $a"
    fi
  done <"$RECEIPT"
  # directories we created, deepest first
  dirs=$(awk -F "$TAB" '$1 == "dir" { print length($2) " " $2 }' "$RECEIPT" | sort -rn | cut -d' ' -f2-)
  if [ $DRY = 1 ]; then
    rec receipt would-change "remove $RECEIPT and empty directories bootstrap created"
    return
  fi
  if [ -n "$NEWREC" ]; then printf '%s' "$NEWREC" >"$RECEIPT"; else rm -f "$RECEIPT" "$RECEIPT.tmp"; fi
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if rmdir "$d" 2>/dev/null; then
      rec dir changed "removed empty $d"
    elif [ -d "$d" ] && [ -n "$NEWREC" ]; then
      printf 'dir\t%s\n' "$d" >>"$RECEIPT"
    fi
  done <<EOF
$dirs
EOF
}

# ---------------------------------------------------------------- main
MODE=apply
[ $DRY = 1 ] && MODE=dry-run
[ $CHECK = 1 ] && MODE=check
[ $UNINSTALL = 1 ] && MODE=uninstall
[ $UNINSTALL = 1 ] && [ $DRY = 1 ] && MODE=uninstall-dry-run

command -v git >/dev/null 2>&1 || {
  echo "bootstrap: git is required" >&2
  exit 1
}
[ $JSON = 1 ] || echo "dotfiles bootstrap $VERSION ($MODE) root=$ROOT home=$HOME"

OVERLAY_CREATED=0
if [ $UNINSTALL = 1 ]; then
  do_uninstall
else
  detect_identity
  link_layers
  setup_overlay
  if [ $CHECK = 1 ]; then
    check_effective
  else
    { [ $SIGN_ON = 1 ] || [ $SIGN_OFF = 1 ]; } && toggle_signing
    { [ $LD_ON = 1 ] || [ $LD_OFF = 1 ]; } && launchd_toggle
    if [ $NO_BIN = 0 ]; then
      case ":$PATH:" in
        *":$BINDIR:"*) rec path ok "$BINDIR is on PATH" ;;
        *) rec path warn "add to your shell profile:  export PATH=\"\$HOME/.local/bin:\$PATH\"  (needed for 'git sync')" ;;
      esac
    fi
  fi
  [ $CHECK = 1 ] || seal_overlay
  check_deps
  manifest
fi

RC=0
if [ $CHECK = 1 ]; then
  [ $PROBLEMS -gt 0 ] && RC=2
else [ $FAILURES -gt 0 ] && RC=1; fi

if [ $JSON = 1 ]; then
  printf '{"schema":"dotfiles-bootstrap/v1","version":"%s","mode":"%s","ok":%s,"exit_code":%s,"backup_dir":%s,"actions":[%s],"manifest":[%s]}\n' \
    "$VERSION" "$MODE" "$([ $RC = 0 ] && echo true || echo false)" "$RC" \
    "$([ $BACKED_UP -gt 0 ] && dot_json_str "$BACKUP_DIR" || echo null)" "$ACTIONS_JSON" "$MANIFEST_JSON"
else
  [ $BACKED_UP -gt 0 ] && echo "backed up $BACKED_UP existing path(s) to $BACKUP_DIR"
  case $MODE in
    check) [ $RC = 0 ] && echo "doctor: healthy" || echo "doctor: $PROBLEMS problem(s)" ;;
    *dry-run) echo "dry-run: nothing changed" ;;
    uninstall) [ $RC = 0 ] && echo "uninstalled." || echo "finished with $FAILURES error(s)" ;;
    *) [ $RC = 0 ] && echo "done. Next: ./bootstrap.sh --check   (edit $OVERLAY to choose a profile)" || echo "finished with $FAILURES error(s)" ;;
  esac
fi
exit $RC
