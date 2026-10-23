# AGENTS.md

Conventions for agents (and humans) working in this repo.

- Scripts are `#!/usr/bin/env bash`, **bash 3.2 compatible** (macOS default):
  no associative arrays, `mapfile`, `${v,,}`, `&>>`. Mind GNU vs BSD tools
  (`sed -i`, `stat`, `date`, `readlink -f`): prefer POSIX forms. Test on
  `/bin/bash` on macOS.
- Agent-DX contract for every command: `--help` (structured sections;
  `--help --json` machine readable), `--json` prints exactly one JSON document
  on stdout with a `schema` field, logs/progress go to stderr, stable exit
  codes, **never prompts** (stdin not a TTY, `CI=1`), secrets never in flags.
- No telemetry, no network except `git fetch` (and `install.sh` downloading what
  you asked for). No personal, host- or org-specific defaults anywhere: examples
  use `acme-corp`, `example-vault`, `example.com`.
- No secrets in the repo. Tests build fake tokens at runtime so the test files
  contain nothing scannable.
- Commits: Conventional Commits with DCO sign-off (`git commit -s`); branches
  `type/issue-slug`; squash merge. The repo's own hooks apply to this repo too.
- Never run `bootstrap.sh` or `git config --global` against a real HOME from a
  test; tests use a temp `HOME`/`XDG_CONFIG_HOME` (see `tests/lib.sh`).
- Format and lint like CI: `shfmt -d` (config in `.editorconfig`) and
  `shellcheck -x` (config in `.shellcheckrc`).
- Layout: `bin/` commands, `lib/common.sh` shared helpers (exemption, profile
  and feature logic, chaining, timeouts), `git/` files symlinked into
  `~/.config/git` (`config` = includes, `presets`, `hooks.inc`, `hooks/`,
  `ignore`, `attributes`), `templates/config.example` (the overlay template),
  `manifest/repos.example.txt`, `launchd/`, `scripts/make-release.sh`,
  `install.sh`, `tests/`, `docs/`.

## Command contract

| Command | `--json` | Exit codes |
|---|---|---|
| `git sync` (`bin/git-sync`) | schema `git-sync/v1`: `repos[]{path,name,status,exempt,default_branch,fetch,branches[]{name,state,upstream,ahead,behind,checked_out,applied,reason,backup},errors[]}`, `errors[]`, `summary` | 0 ok, 2 attention, 3 fetch error, 1 internal, 64 usage |
| `bootstrap.sh` | schema `dotfiles-bootstrap/v1`: `mode` (`apply dry-run check uninstall uninstall-dry-run`), `ok`, `exit_code`, `backup_dir`, `actions[]{id,status,detail}`, `manifest[]` | 0 ok, 1 action failed, 2 `--check` found problems, 64 usage |
| `install.sh` | schema `dotfiles-install/v1`: `ok`, `status`, `version`, `prefix`, `dest`, `sha256`, `detail` | 0 ok, 1 failure, 3 download failed, 4 checksum mismatch, 64 usage |
| `bash tests/run.sh` | n/a | 0 all pass, 1 failures |
| hooks | n/a | 0 pass, 1 block (git semantics) |

Action statuses: `ok changed would-change missing wrong warn error skipped`.
Exemption and feature logic live only in `dot_is_exempt` / `dot_feature`
(`lib/common.sh`); do not copy them. When adding a hook: source the lib, gate on
`dot_feature <name>` and `dot_is_exempt`, finish with `dot_chain "$HOOK" "$@"`,
add the feature to the profile table in `dot_feature`, README and
`docs/GIT-CONFIG.md`, and add tests in `tests/test_hooks.sh` and
`tests/test_profiles.sh`.

The version lives in `VERSION` (managed by release-please); scripts read it via
`dot_version`. Do not hard-code versions.
