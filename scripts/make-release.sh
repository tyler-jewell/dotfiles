#!/usr/bin/env bash
# make-release.sh VERSION OUTDIR
# Builds OUTDIR/dotfiles-VERSION.tar.gz with `git archive` (tracked files of
# HEAD only, honouring export-ignore) and OUTDIR/SHA256SUMS. Used by the
# release workflow and by tests/test_install.sh. Bash 3.2 compatible.
set -eu
[ $# -eq 2 ] || {
  echo "usage: make-release.sh VERSION OUTDIR" >&2
  exit 64
}
ver=${1#v}
out=$2
here=$(cd -P "$(dirname "$0")/.." && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)
tar_name=dotfiles-$ver.tar.gz
git -C "$here" archive --format=tar.gz --prefix="dotfiles-$ver/" -o "$out/$tar_name" HEAD
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$out" && sha256sum "$tar_name" >SHA256SUMS)
else
  (cd "$out" && shasum -a 256 "$tar_name" >SHA256SUMS)
fi
echo "$out/$tar_name"
