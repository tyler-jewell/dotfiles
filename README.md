# dotfiles

[![ci](https://github.com/tyler-jewell/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/tyler-jewell/dotfiles/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Safe, opt-in git defaults for your machine: a global git config layer, global
git hooks that **chain to each repo's own hooks**, and `git sync`, a
fast-forward-only branch syncer. Nothing is personal or host-specific: you
choose a profile, add your own overlay, and can remove it all with one command.

- **Opt in gradually**: `minimal` runs a secret scan and nothing else.
- **Reversible**: `./bootstrap.sh --uninstall` restores your machine byte for byte.
- **Auditable**: plain bash, no dependencies beyond git, no network except
  `git fetch`, no telemetry ([threat model](docs/THREAT-MODEL.md)).
- **Agent friendly**: every command has `--json`, documented exit codes, and
  never prompts on a non-TTY or `CI=1`.

## Quickstart (60 seconds)

```sh
git clone https://github.com/tyler-jewell/dotfiles ~/dotfiles   # any location works
cd ~/dotfiles
./bootstrap.sh --dry-run        # exactly what would change; nothing is written
./bootstrap.sh                  # apply (anything it replaces is moved to a backup dir)
./bootstrap.sh --check          # doctor; add --json for machines
export PATH="$HOME/.local/bin:$PATH"   # once, in your shell profile, for `git sync`
./bootstrap.sh --uninstall      # remove exactly what was installed, restore backups
```

Then open `~/.config/dotfiles/config` (created for you, fully commented) and
pick a profile. Prefer a verified download over `git clone`? See
[install.sh](#optional-verified-release-download).

## What changes on disk

| Path | What | Layer |
|---|---|---|
| `~/.config/git/config` | symlink; only `[include]`s the files below | always |
| `~/.config/git/{presets,ignore,attributes}` | symlinks: git defaults, global ignore and attributes | config (`--no-config` skips) |
| `~/.config/git/{hooks.inc,hooks}` | symlinks: sets `core.hooksPath`, the hook scripts | hooks (`--no-hooks` skips) |
| `~/.config/dotfiles/config` | **your overlay**, a real file created once from a commented template, never overwritten, included *last* | always |
| `~/.config/dotfiles/repos.txt` | optional repo manifest you write yourself | never created |
| `~/.local/bin/{git-sync,dotfiles-bootstrap}` | symlinks | bin (`--no-bin` skips) |
| `~/.local/state/dotfiles/` | `receipt` (what to undo) and `backup-<ts>/` (originals) | always |
| `~/Library/LaunchAgents/dev.dotfiles.git-sync.plist` | only with `--install-launchd` (macOS) | opt-in |

Bootstrap never runs `git config --global`, never edits shell rc files, never
touches an existing `~/.gitconfig`, and writes only under `$HOME`.

## Profiles

Set `[dotfiles] profile = ...` in your overlay (or per repo with
`git config --local dotfiles.profile minimal`). Default: `standard`.

| Feature (`hooks.<name>`) | minimal | standard | strict | What it does |
|---|:-:|:-:|:-:|---|
| `secretScan` | yes | yes | yes | pre-commit: secret patterns, plaintext `.env` files, files over 5 MB |
| `conventionalCommits` | | yes | yes | commit-msg: Conventional Commits header |
| `sync` | | yes | yes | post-commit/checkout/merge: background, throttled, fetch-only `git-sync --hook` |
| `branchName` | | | yes | pre-push: branch must match `hooks.branchNamePattern` (default `type/[issue-]slug`) |
| `protectMain` | | | yes | pre-push: no direct push to `main`/`master`, no force-push or delete (`GIT_ALLOW_MAIN_PUSH=1` allows a direct push once) |

Any feature can be forced on or off, globally or per repo, regardless of
profile: `git config --local hooks.branchName false`. The git presets
(`pull.ff=only`, ...) are a separate layer and do not depend on the profile.
Moving between profiles is one line; details and every setting in
[docs/GIT-CONFIG.md](docs/GIT-CONFIG.md), gradual adoption in
[docs/ADOPTING.md](docs/ADOPTING.md).

## Secrets: stay away from `.env` files

The pre-commit hook **blocks any `.env` or `.env.*` file** (only `*.example` and
`*.sample` templates pass) and the global ignore hides them. The recommended
pattern is to commit *references*, never values, and inject at runtime. With
1Password that is an `op.refs` file of `op://` links:

```sh
# op.refs  (safe to commit)
API_TOKEN=op://example-vault/example-item/field
op run --env-file=op.refs -- ./my-command
```

This is one option: the hooks only block plaintext env files and work with any
secret manager. [`op-doctor`](https://github.com/tyler-jewell/op-doctor) is an
optional companion for checking that `op://` references resolve.

## Exempting repos

Repos that follow their own conventions can be exempt (no global checks, no
sync; their own hooks still run). In your overlay:

```ini
[hooks]
	exemptOrigins = *github.com/acme-corp/*
```

Globs are case-insensitive and match every remote URL. Per repo:
`git config --local hooks.exempt true` (or `false` to force enforcement).
Environment: `GIT_HOOKS_EXEMPT=1`.

## How the hooks chain

`core.hooksPath` replaces `.git/hooks`, which would silently disable hooks
installed there. Every global hook therefore runs its own checks and then
executes `<git-common-dir>/hooks/<name>` if present and executable (stdin is
replayed for `pre-push`; exit status propagates). Hook names we do not
implement are symlinks to `_passthrough`, which only chains. If a tool such as
lefthook or husky sets a *local* `core.hooksPath`, that local value wins and
these hooks do not run in that repo (see [ADOPTING](docs/ADOPTING.md)).

## git sync

```sh
git sync                   # current repo
git sync --all             # every manifest entry with sync=yes
git sync --root ~/code     # every repo directly under ~/code
git sync --dry-run --json
git sync --prune-merged    # delete `gone` branches merged into origin/<default> (bundle backup first)
```

Never merges, rebases, stashes, resets or forces. Per-branch states:
`up-to-date | fast-forwarded | behind-skipped-dirty | behind-skipped-worktree |
ahead | diverged | gone | no-upstream | pruned`. Exit codes: `0` fine, `2`
attention, `3` fetch/network error, `64` usage. The manifest (optional) is
`~/.config/dotfiles/repos.txt`; see
[manifest/repos.example.txt](manifest/repos.example.txt). Optional scheduler:
`./bootstrap.sh --install-launchd` (macOS, every 15 minutes).

## Compatibility

| | Status |
|---|---|
| macOS, system `/bin/bash` 3.2 | developed and tested (git 2.54); CI runs macOS too |
| Linux, bash 4/5 | CI on `ubuntu-latest` plus Debian 12 and Ubuntu 24.04 containers. The author has not run it on Linux locally, so treat CI as the evidence |
| git | **2.35 or newer** (`merge.conflictStyle=zdiff3`); the config keys are ignored by newer-than-key versions and the minimum comes from the git release notes, not from running every old git. CI exercises the distro gits it can reach. |
| Windows | not supported (use WSL) |
| Needed tools | bash, git, coreutils-style `sed awk grep find sort cksum`. Optional: `gitleaks` (bigger ruleset), `jq` (reading `--json`) |

## Optional verified release download

`install.sh` downloads a release tarball and `SHA256SUMS`, **verifies the
checksum before extracting anything**, and installs to
`~/.local/share/dotfiles/<version>` (`--prefix`, `--version`, `--dry-run`,
`--json`). It never pipes into a shell and does not run bootstrap for you. A
plain `git clone` is equally supported. Release tarballs carry GitHub build
provenance (`gh attestation verify <file> --repo tyler-jewell/dotfiles`).

## More

[Threat model](docs/THREAT-MODEL.md) | [Comparison](docs/COMPARISON.md) |
[FAQ](docs/FAQ.md) | [Adopting](docs/ADOPTING.md) |
[Workflow](docs/WORKFLOW.md) | [Git config reference](docs/GIT-CONFIG.md) |
[Releasing](docs/RELEASING.md) | [Contributing](CONTRIBUTING.md) |
[Security](SECURITY.md) | [Changelog](CHANGELOG.md) | [AGENTS.md](AGENTS.md)

Tests: `bash tests/run.sh` (bash + git; jq optional). Apache-2.0.
