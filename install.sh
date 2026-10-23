#!/usr/bin/env bash
# install.sh - OPTIONAL downloader for a released version of these dotfiles.
# Plain `git clone` works just as well. This script:
#   1. downloads dotfiles-<version>.tar.gz and SHA256SUMS from a GitHub release,
#   2. VERIFIES the tarball's sha256 against SHA256SUMS before doing anything else,
#   3. extracts it to <prefix>/<version> and points <prefix>/current at it.
# It never pipes into a shell and never runs bootstrap.sh for you: read the
# code, then run <prefix>/current/bootstrap.sh --dry-run yourself.
# The only network access is the download itself (curl or wget).
# Bash 3.2 compatible.
REPO=${DOTFILES_REPO:-tyler-jewell/dotfiles}
BASE=${DOTFILES_BASE_URL:-https://github.com/$REPO/releases}

usage_text() {
  cat <<'EOF'
install.sh - download and verify a release of the dotfiles (optional)

USAGE
  ./install.sh [--version X.Y.Z|latest] [--prefix DIR] [--dry-run] [--json]

OPTIONS
  --version V    release to install, e.g. 0.1.0 (default: latest)
  --prefix DIR   install root (default: ${XDG_DATA_HOME:-~/.local/share}/dotfiles)
  --dry-run, -n  resolve and print what would happen; download nothing
  --json         one JSON document on stdout (schema dotfiles-install/v1)
  --help [--json]

ENVIRONMENT
  DOTFILES_REPO      owner/name to download from (default tyler-jewell/dotfiles)
  DOTFILES_BASE_URL  release base URL override (https://, or file:// for testing)

EXIT CODES
  0   installed (or --dry-run described it)
  1   unexpected failure (extract, filesystem)
  3   download failed
  4   checksum verification failed; nothing was extracted
  64  usage error

Never prompts. After installing, run:  <prefix>/current/bootstrap.sh --dry-run
EOF
}
usage_json() {
  cat <<'EOF'
{"name":"install.sh","schema":"dotfiles-install/v1","interactive":false,
 "options":["--version","--prefix","--dry-run","--json","--help"],
 "exit_codes":{"0":"installed","1":"failure","3":"download failed","4":"checksum mismatch","64":"usage error"}}
EOF
}

VER=latest PREFIX=${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles DRY=0 JSON=0 HELP=0
while [ $# -gt 0 ]; do
  case $1 in
    --version | --prefix)
      [ $# -ge 2 ] || {
        echo "install: $1 needs a value" >&2
        exit 64
      }
      if [ "$1" = --version ]; then VER=$2; else PREFIX=$2; fi
      shift
      ;;
    --dry-run | -n) DRY=1 ;;
    --json) JSON=1 ;;
    -h | --help) HELP=1 ;;
    *)
      echo "install: unknown argument: $1 (try --help)" >&2
      exit 64
      ;;
  esac
  shift
done
if [ $HELP = 1 ]; then
  if [ $JSON = 1 ]; then usage_json; else usage_text; fi
  exit 0
fi
VER=${VER#v}
case $VER in latest | [0-9]*.[0-9]*.[0-9]*) ;; *)
  echo "install: --version must be X.Y.Z or latest" >&2
  exit 64
  ;;
esac
case $VER in *[!0-9A-Za-z.+-]*)
  echo "install: bad version string" >&2
  exit 64
  ;;
esac

say() { [ $JSON = 1 ] || printf '%s\n' "$*"; }
STATUS=error DETAIL="" DEST="" SHA=""
finish() { # finish RC
  if [ $JSON = 1 ]; then
    printf '{"schema":"dotfiles-install/v1","ok":%s,"status":"%s","version":"%s","prefix":"%s","dest":"%s","sha256":"%s","detail":"%s"}\n' \
      "$([ "$1" = 0 ] && echo true || echo false)" "$STATUS" "$VER" "$PREFIX" "$DEST" "$SHA" "$(printf '%s' "$DETAIL" | tr -d '"\134' | tr '\n' ' ')"
  elif [ -n "$DETAIL" ]; then
    printf 'install: %s\n' "$DETAIL" >&2
  fi
  exit "$1"
}
fetch() { # fetch URL OUTFILE
  case $1 in
    file://*) cp "${1#file://}" "$2" 2>/dev/null ;;
    *)
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 -o "$2" "$1" 2>/dev/null
      elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1" 2>/dev/null
      else return 1; fi
      ;;
  esac
}
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else return 1; fi
}

if [ "$VER" = latest ]; then
  case $BASE in
    file://*)
      DETAIL="--version is required with a file:// base"
      finish 64
      ;;
  esac
  if [ $DRY = 1 ]; then
    STATUS=would-install DETAIL=""
    say "would resolve the latest release of $REPO and install it under $PREFIX"
    finish 0
  fi
  loc=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$BASE/latest" 2>/dev/null)
  VER=${loc##*/v}
  case $VER in [0-9]*.[0-9]*.[0-9]*) ;; *)
    DETAIL="cannot resolve the latest release from $BASE/latest"
    finish 3
    ;;
  esac
fi
TAR=dotfiles-$VER.tar.gz
DEST=$PREFIX/$VER
if [ $DRY = 1 ]; then
  STATUS=would-install
  say "would download $BASE/download/v$VER/$TAR"
  say "would verify it against $BASE/download/v$VER/SHA256SUMS, then extract to $DEST"
  finish 0
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install.XXXXXX") || {
  DETAIL="cannot create a temp dir"
  finish 1
}
trap 'rm -rf "$TMP"' EXIT
say "downloading $TAR and SHA256SUMS"
fetch "$BASE/download/v$VER/$TAR" "$TMP/$TAR" || {
  DETAIL="download failed: $BASE/download/v$VER/$TAR"
  STATUS=download-failed
  finish 3
}
fetch "$BASE/download/v$VER/SHA256SUMS" "$TMP/SHA256SUMS" || {
  DETAIL="download failed: $BASE/download/v$VER/SHA256SUMS"
  STATUS=download-failed
  finish 3
}
want=$(awk -v f="$TAR" '$2 == f || $2 == "*" f { print $1; exit }' "$TMP/SHA256SUMS")
SHA=$(sha256_of "$TMP/$TAR") || {
  DETAIL="need sha256sum or shasum to verify the download"
  finish 1
}
if [ -z "$want" ] || [ "$want" != "$SHA" ]; then
  STATUS=checksum-mismatch
  DETAIL="sha256 of $TAR is $SHA but SHA256SUMS says '${want:-<no entry>}'; nothing was extracted"
  finish 4
fi
say "sha256 verified: $SHA"
# Refuse archives that could write outside the destination.
if tar -tzf "$TMP/$TAR" | grep -E -q '(^/|(^|/)\.\.(/|$))'; then
  STATUS=unsafe-archive
  DETAIL="archive contains absolute or parent-relative paths; refusing"
  finish 4
fi
mkdir -p "$DEST.new.$$" && tar -xzf "$TMP/$TAR" -C "$DEST.new.$$" --strip-components=1 || {
  rm -rf "$DEST.new.$$"
  DETAIL="extract failed"
  finish 1
}
if [ ! -x "$DEST.new.$$/bootstrap.sh" ]; then
  rm -rf "$DEST.new.$$"
  DETAIL="archive does not look like these dotfiles (no bootstrap.sh)"
  finish 1
fi
rm -rf "$DEST"
mv "$DEST.new.$$" "$DEST" && ln -sfn "$DEST" "$PREFIX/current" || {
  DETAIL="cannot finalize $DEST"
  finish 1
}
STATUS=installed
say "installed $VER to $DEST (current -> $DEST)"
say "next: $PREFIX/current/bootstrap.sh --dry-run"
finish 0
