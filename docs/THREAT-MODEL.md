# Threat model

Global git hooks execute code in **every repository you touch**, including
ones you just cloned from strangers. That deserves a straight account of what
can go wrong and what this project does about it.

## What runs, and when

Only the scripts in `git/hooks/` (plus the repo's own hooks, which you would
already be running without us). They run on `git commit`, `git push`,
`git checkout`, `git merge`. List them: `ls -l ~/.config/git/hooks/`. Every
file is a short bash script that sources `lib/common.sh`.

## What can go wrong

| Risk | Reality here | Mitigation |
|---|---|---|
| **A hook is malicious or buggy** and runs in all your repos | Real: that is the nature of `core.hooksPath` | Small, readable bash; no downloads at hook time; tests; `--no-verify`; instant disable below |
| **Supply chain**: a compromised release or dependency | There are no runtime dependencies. Releases are built in CI from a tagged commit, carry SHA256SUMS and GitHub build provenance; `install.sh` verifies the checksum before extracting. CI actions are pinned by commit SHA and updated by Dependabot PRs | Prefer `git clone` + read the diff before `git pull`; verify attestations with `gh attestation verify` |
| **Hooks edited after install** | The linked directory is *your* clone, so anything that can write to it can change what runs in every repo | Keep the clone user-owned and not world-writable; `bootstrap --check` flags missing/wrong links; commit signing/review on the clone |
| **A repo's own hook is hostile** | Same risk as without us. We chain to it (that is the point), we do not sandbox it | Review hooks before running git in unknown repos |
| **Exempt/override misuse** | `hooks.exemptOrigins` and per-repo config are plain git config; a repo cannot set *global* config, but a repo-local `.git/config` can turn features off for that repo | Expected; local config is yours to set |
| **Secret scan false sense of security** | The scanner is a safety net with a short pattern list (plus `gitleaks` when installed). `--no-verify` bypasses it by design | Server-side scanning and rotation still apply |
| **Background sync touches the network** | `git-sync --hook` only runs `git fetch` against remotes the repo already has, throttled to once per 5 minutes, never updates your checked-out branch | `hooks.sync=false` or `GIT_SYNC_DISABLE=1` |

## Why symlinks into a user-owned directory

`core.hooksPath` needs one stable path. The hooks live in your clone; bootstrap
only creates symlinks from `~/.config/git/` to it. Consequences: nothing is
copied (what you read is what runs), upgrades are `git pull`, everything is
owned by your user (no root, no system paths), and removal is deleting links,
which `--uninstall` does exactly, from a receipt, restoring backups.

## Audit what runs

```sh
ls -l ~/.config/git/                # links and where they point
./bootstrap.sh --check --json       # machine-readable health report
git config --show-origin --get-regexp '^(dotfiles|hooks|core\.hooksPath)'
cat ~/.local/state/dotfiles/receipt # everything bootstrap created
GIT_TRACE=1 git commit ...          # shows hook execution
```

## Disable instantly

| Scope | How |
|---|---|
| One command | `git commit --no-verify`, `git push --no-verify` |
| This shell | `export GIT_HOOKS_EXEMPT=1` (all checks off, repo hooks still run) |
| One repo | `git config --local hooks.exempt true`, or switch single features off |
| Background sync | `GIT_SYNC_DISABLE=1` or `hooks.sync=false` |
| Everything | `./bootstrap.sh --uninstall` (or just remove `~/.config/git/hooks.inc`) |

## What it never does

- **No network** except `git fetch` (inside `git sync` and its hook trigger) and,
  only if you choose to run it, `install.sh` downloading a release you asked for.
  `bootstrap.sh --clone-repos` runs `git clone` for manifest entries you wrote.
- **No telemetry**, analytics, update checks or phoning home of any kind.
- **No sudo** or writes outside `$HOME`; no shell rc edits; no
  `git config --global` calls; no reading of credentials, keys or env secrets.
- **No secrets in flags.** `--enable-signing` accepts only a *public* key and
  refuses anything that looks like a private key. Findings print a rule name and
  location, never the secret.
- Never deletes branches unless you pass `--prune-*`, and then only after
  writing and verifying a git bundle backup.

## Reporting problems

See [SECURITY.md](../SECURITY.md): GitHub private vulnerability reporting.
