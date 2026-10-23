#!/usr/bin/env bash
# install.sh: checksum verification, dry-run, prefix, failure modes. Uses a
# file:// "release" built by scripts/make-release.sh; no network.
. "$(dirname "$0")/lib.sh"
t_init
IN=$ROOT/install.sh
VER=$(awk '{print $1; exit}' "$ROOT/VERSION")

echo "-- usage"
run "unknown flag" 64 "$IN" --nope
run "bad version" 64 "$IN" --version banana
run "missing value" 64 "$IN" --prefix
json_valid "help --json" "$("$IN" --help --json)"
assert_contains "help documents exit codes" "$("$IN" --help)" "EXIT CODES"
assert_contains "help documents --dry-run" "$("$IN" --help)" "--dry-run"

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || ! git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
  echo "  (not a git checkout: release build tests skipped)"
  summary
  exit $?
fi

REL=$T/rel
mkdir -p "$REL/download/v$VER"
"$ROOT/scripts/make-release.sh" "$VER" "$REL/download/v$VER" >/dev/null
export DOTFILES_BASE_URL=file://$REL

echo "-- dry-run downloads and writes nothing"
before=$(snapshot "$T/home")
run "dry-run" 0 "$IN" --version "$VER" --prefix "$T/home/prefix" --dry-run --json
json_valid "dry-run json" "$OUT"
assert_eq "dry-run status" would-install "$(jq_get .status "$OUT")"
assert_eq "dry-run wrote nothing" "$before" "$(snapshot "$T/home")"
run "latest needs a version for file://" 64 "$IN"

echo "-- verified install"
run "install" 0 "$IN" --version "$VER" --prefix "$T/home/prefix" --json
json_valid "install json" "$OUT"
assert_eq "installed status" installed "$(jq_get .status "$OUT")"
want=$(awk '{print $1}' "$REL/download/v$VER/SHA256SUMS")
assert_eq "reported sha256 matches SHA256SUMS" "$want" "$(jq_get .sha256 "$OUT")"
assert_file "bootstrap extracted" "$T/home/prefix/$VER/bootstrap.sh"
assert_eq "current symlink" "$T/home/prefix/$VER" "$(readlink "$T/home/prefix/current")"
assert_eq "extracted tree reports the same version" "bootstrap.sh $VER" "$("$T/home/prefix/current/bootstrap.sh" --version)"
assert_no_file "tests are shipped but .github is not" "$T/home/prefix/$VER/.github"
run "reinstall same version is idempotent" 0 "$IN" --version "v$VER" --prefix "$T/home/prefix"
run "extracted bootstrap.sh --help works" 0 "$T/home/prefix/$VER/bootstrap.sh" --help

echo "-- tampered tarball is rejected before anything is extracted"
cp -R "$REL" "$T/rel-bad"
printf 'x' >>"$T/rel-bad/download/v$VER/dotfiles-$VER.tar.gz"
DOTFILES_BASE_URL=file://$T/rel-bad run "tampered" 4 "$IN" --version "$VER" --prefix "$T/home/prefix2" --json
assert_eq "checksum-mismatch status" checksum-mismatch "$(jq_get .status "$OUT")"
assert_no_file "nothing extracted" "$T/home/prefix2"

echo "-- SHA256SUMS without an entry is rejected"
cp -R "$REL" "$T/rel-noent"
echo "0000000000000000000000000000000000000000000000000000000000000000  other.tar.gz" >"$T/rel-noent/download/v$VER/SHA256SUMS"
DOTFILES_BASE_URL=file://$T/rel-noent run "no entry" 4 "$IN" --version "$VER" --prefix "$T/home/prefix3"
assert_no_file "nothing extracted (no entry)" "$T/home/prefix3"

echo "-- download failures"
DOTFILES_BASE_URL=file://$T/nowhere run "missing release" 3 "$IN" --version "$VER" --prefix "$T/home/prefix4"
assert_no_file "nothing created" "$T/home/prefix4"

echo "-- archives with path traversal are refused even when the checksum matches"
if command -v python3 >/dev/null 2>&1; then
  cp -R "$REL" "$T/rel-evil"
  python3 -I - "$T/rel-evil/download/v$VER" "$VER" <<'PYEOF'
import io, sys, tarfile, hashlib
d, v = sys.argv[1], sys.argv[2]
name = "dotfiles-%s.tar.gz" % v
with tarfile.open(d + "/" + name, "w:gz") as t:
    data = b"evil"
    ti = tarfile.TarInfo("dotfiles-%s/../../escape.txt" % v)
    ti.size = len(data)
    t.addfile(ti, io.BytesIO(data))
h = hashlib.sha256(open(d + "/" + name, "rb").read()).hexdigest()
open(d + "/SHA256SUMS", "w").write("%s  %s\n" % (h, name))
PYEOF
  DOTFILES_BASE_URL=file://$T/rel-evil run "path traversal" 4 "$IN" --version "$VER" --prefix "$T/home/prefix5"
  assert_no_file "nothing escaped" "$T/home/escape.txt"
  assert_no_file "nothing extracted (traversal)" "$T/home/prefix5"
fi

summary
