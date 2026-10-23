#!/usr/bin/env bash
# lib/common.sh - shared helpers for the global git hooks and bin/git-sync.
# Sourced, never executed. Must stay compatible with bash 3.2 (macOS default).
# shellcheck shell=bash

# dot_version ROOT -> version string from ROOT/VERSION ("unknown" if absent).
# The file holds "X.Y.Z" optionally followed by a release-please marker comment.
dot_version() {
  local v=""
  [ -f "$1/VERSION" ] && v=$(awk 'NF { print $1; exit }' "$1/VERSION" 2>/dev/null)
  printf '%s\n' "${v:-unknown}"
}

# dot_config_dir -> per-user overlay directory (config + repos.txt).
dot_config_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"; }

# dot_profile [DIR] -> minimal | standard | strict (unknown values fall back to standard).
dot_profile() {
  local p
  p=$(dot_lower "$(git -C "${1:-.}" config --get dotfiles.profile 2>/dev/null)")
  case $p in minimal | standard | strict) printf '%s\n' "$p" ;; *) printf 'standard\n' ;; esac
}

# dot_feature NAME [DIR]
# Exit 0 when the hook feature NAME is enabled for the repo at DIR (default cwd).
# An explicit git config boolean hooks.NAME (any scope; local beats global)
# wins; otherwise the dotfiles.profile decides:
#   minimal  : secretScan
#   standard : + conventionalCommits, sync
#   strict   : + branchName, protectMain
dot_feature() {
  local name=$1 v prof
  v=$(git -C "${2:-.}" config --type=bool --get "hooks.$name" 2>/dev/null)
  case $v in true) return 0 ;; false) return 1 ;; esac
  prof=$(dot_profile "${2:-.}")
  case $name in
  secretScan) return 0 ;;
  conventionalCommits | sync) [ "$prof" != minimal ] ;;
  branchName | protectMain) [ "$prof" = strict ] ;;
  *) return 1 ;;
  esac
}

# dot_default_manifest -> default repo manifest path.
dot_default_manifest() { printf '%s/repos.txt\n' "$(dot_config_dir)"; }

# dot_lower STRING -> lowercase on stdout (bash 3.2 has no ${var,,}).
dot_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# dot_realpath PATH -> physical absolute path with symlinks resolved.
dot_realpath() {
  local p=$1 d
  while [ -L "$p" ]; do
    d=$(cd -P "$(dirname "$p")" 2>/dev/null && pwd) || break
    p=$(readlink "$p")
    case $p in /*) ;; *) p="$d/$p" ;; esac
  done
  d=$(cd -P "$(dirname "$p")" 2>/dev/null && pwd) || {
    printf '%s\n' "$p"
    return
  }
  printf '%s/%s\n' "$d" "$(basename "$p")"
}

# dot_is_exempt [DIR]
# Exit 0 when the repo at DIR (default: cwd) must not be subject to our hooks
# or sync rules. Sources of exemption, first match wins:
#   GIT_HOOKS_EXEMPT=1                     (environment)
#   hooks.exempt=true|false                (per-repo git config; false forces
#                                           enforcement even if an origin matches)
#   any remote URL matching a glob in      hooks.exemptOrigins (multi-valued
#   git config) or $DOTFILES_EXEMPT_ORIGINS (whitespace separated globs)
# Matching is case-insensitive. With no pattern configured nothing is exempt.
dot_is_exempt() {
  local dir=${1:-.} url pats p u
  [ "${GIT_HOOKS_EXEMPT:-}" = 1 ] && return 0
  case $(git -C "$dir" config --type=bool --get hooks.exempt 2>/dev/null) in
  true) return 0 ;;
  false) return 1 ;; # explicit per-repo opt-in to enforcement beats origin patterns
  esac
  pats=$(git -C "$dir" config --get-all hooks.exemptOrigins 2>/dev/null)
  [ -n "${DOTFILES_EXEMPT_ORIGINS:-}" ] && pats="$pats
$DOTFILES_EXEMPT_ORIGINS"
  [ -z "$pats" ] && return 1
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    u=$(dot_lower "${url#* }")
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      p=$(dot_lower "$p")
      # shellcheck disable=SC2254  # $p is deliberately a glob pattern
      case $u in $p) return 0 ;; esac
    done <<EOF
$pats
EOF
  done <<EOF
$(git -C "$dir" config --get-regexp '^remote\..*\.url$' 2>/dev/null)
EOF
  return 1
}

# dot_common_dir -> absolute git common dir (shared by all worktrees).
dot_common_dir() {
  local d
  d=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  (cd "$d" 2>/dev/null && pwd -P)
}

# dot_chain NAME [ARGS...]
# Run the repository's own hook NAME (core.hooksPath replaces .git/hooks, so
# we must forward to it). If HOOK_STDIN_FILE is set it is fed to the hook's
# stdin (pre-push). Never recurses into ourselves. Exits with the hook's status
# (or returns 0 when there is nothing to chain to).
dot_chain() {
  local name=$1 common repo_hook self_dir
  shift
  common=$(dot_common_dir) || return 0
  repo_hook="$common/hooks/$name"
  [ -f "$repo_hook" ] && [ -x "$repo_hook" ] || return 0
  # core.hooksPath may point at the very directory we live in; avoid a loop.
  self_dir=$(cd -P "$(dirname "$0")" 2>/dev/null && pwd -P)
  [ "$self_dir" = "$(cd -P "$common/hooks" && pwd -P)" ] && return 0
  if [ -n "${HOOK_STDIN_FILE:-}" ]; then
    "$repo_hook" "$@" <"$HOOK_STDIN_FILE"
    exit $?
  fi
  exec "$repo_hook" "$@"
}

# dot_timeout SECONDS CMD... -> run CMD, kill after SECONDS. 124/142 = timeout.
dot_timeout() {
  local secs=$1
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV or exit 127' "$secs" "$@"
  else
    "$@"
  fi
}

# dot_warn / dot_err: stderr helpers (hooks stay quiet on success).
dot_warn() { printf 'warning: %s\n' "$*" >&2; }
dot_err() { printf 'error: %s\n' "$*" >&2; }

# dot_json_str STRING -> JSON string literal (with quotes). jq-free.
dot_json_str() {
  local s
  s=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\013\014\016-\037' | tr '\n\t\r' '   ' |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '"%s"' "$s"
}
