# Configuration reference

## Layers and precedence

`~/.config/git/config` (a symlink to `git/config`) contains only includes, in
this order. Later wins:

1. `presets` (plus `ignore` and `attributes`): git defaults (`bootstrap --no-config` skips them)
2. `hooks.inc`: `core.hooksPath` (`bootstrap --no-hooks` skips)
3. `../dotfiles/config`: **your overlay**, relative to the link so it follows
   `XDG_CONFIG_HOME` (default `~/.config/dotfiles/config`)

Missing files are ignored by git. A `~/.gitconfig` is read *after* all of these
and wins where keys overlap (`bootstrap --check` warns). A repo's
`.git/config` beats everything: that is how per-repo opt-out works.

## Profile and hook switches

Defaults come from `dotfiles.profile` (`minimal | standard | strict`; unset or
unknown means `standard`). An explicit boolean `hooks.<name>` overrides the profile.

| Setting | Default | Purpose |
|---|---|---|
| `dotfiles.profile` | `standard` | which features are on (table in the README) |
| `hooks.secretScan` | profile (always on) | pre-commit: secret patterns, plaintext `.env*` (only `*.example`/`*.sample` pass), files over `GIT_MAX_FILE_BYTES` (5 MB). Adds `gitleaks` if installed |
| `hooks.conventionalCommits` | standard+ | commit-msg: header `type(scope)!: subject` (max 100) |
| `hooks.branchName` | strict | pre-push: branch names must match the pattern below |
| `hooks.branchNamePattern` | `^(feat\|fix\|docs\|style\|refactor\|perf\|test\|build\|ci\|chore\|revert)/([0-9]+-)?[a-z0-9][a-z0-9-]*$` | extended regex; `main`/`master` are never checked by this |
| `hooks.protectMain` | strict | pre-push: no direct push to `main`/`master`; force-push and deletion always refused. Env `GIT_ALLOW_MAIN_PUSH=1` allows one direct push |
| `hooks.sync` | standard+ | post-commit/checkout/merge: background throttled `git-sync --hook` (fetch only) |
| `hooks.issueFooter` | off | prepare-commit-msg: append `Refs: #N` from a `type/N-slug` branch |
| `hooks.exemptOrigins` | none | multi-valued case-insensitive globs against every remote URL; matching repos get no global checks and no sync |
| `hooks.exempt` | unset | per repo `true` exempts, `false` forces enforcement even if an origin matches |
| `sync.hookUpdateCurrent` | off | let the background trigger fast-forward the checked-out branch |

Environment: `GIT_HOOKS_EXEMPT=1` (all checks off), `GIT_SYNC_DISABLE=1`,
`GIT_ALLOW_MAIN_PUSH=1`, `GIT_MAX_FILE_BYTES`, `DOTFILES_SECRET_SCANNER=builtin`
(skip gitleaks), `DOTFILES_EXEMPT_ORIGINS` (whitespace separated globs).
Inline scanner escape: `secret-scan:allow` on the line.

**Upgrade/downgrade path**: change `dotfiles.profile` (or one switch). Nothing
is stored besides git config; effect is immediate in the next command.

## Presets (`git/presets`)

Independent of the profile. Needs git 2.35+.

| Setting | Why |
|---|---|
| `init.defaultBranch=main` | consistent default |
| `pull.ff=only` | a pull never creates a merge or rebases behind your back |
| `fetch.prune`, `fetch.pruneTags=false` | drop deleted remote branches (needed so `git sync` sees `gone`) but never delete local tags |
| `push.default=simple`, `push.autoSetupRemote`, `push.followTags` | push the current branch, set upstream, push annotated tags |
| `rebase.autoStash=false`, `rebase.autoSquash=true` | no silent stashing; honour `fixup!` |
| `merge.conflictStyle=zdiff3` | show the ancestor, trim shared lines (git 2.35+) |
| `rerere.enabled` | remember conflict resolutions |
| `diff.algorithm=histogram`, `diff.colorMoved`, `diff.renames=copies` | better hunks |
| `branch.sort=-committerdate`, `tag.sort=version:refname` | recent first; v1.10 after v1.9 |
| `column.ui`, `commit.verbose`, `status.showStash` | readability |
| `transfer/fetch/receive.fsckObjects` | reject corrupt objects early |
| `core.untrackedCache`, `core.quotePath=false` | faster status; readable UTF-8 paths |
| `maintenance.strategy=incremental` | used once you run `git maintenance start` |
| `core.excludesFile`, `core.attributesFile` | `git/ignore`, `git/attributes` |

Deliberately **not** set: credential helpers, signing, `gpg.format`,
`url.insteadOf`, `core.editor`, `core.pager`, `core.autocrlf`, `core.fsmonitor`,
`help.autocorrect`. They are personal or environment-specific; the overlay
template shows how to add them (for example the GitHub CLI credential helper).

## Global ignore

OS cruft, `node_modules/`, `*.log`, editor swap files, `.idea/`, AI-agent local
files (`.claude/settings.local.json`, `CLAUDE.local.md`), and plaintext env
files (`.env`, `.env.*`; `*.example`, `*.sample` and `op.refs` are not ignored).
A repo's `.gitignore` can re-include anything.

## Signing

`./bootstrap.sh --enable-signing --signing-key ~/.ssh/id_ed25519.pub` (or
`key::ssh-ed25519 AAAA...`) writes `user.signingkey`, `gpg.format=ssh`,
`commit.gpgsign` and `tag.gpgsign` to your overlay. Add
`--signing-program PATH` for a signer such as 1Password's `op-ssh-sign`
(`/Applications/1Password.app/Contents/MacOS/op-ssh-sign` on macOS); otherwise
git uses `ssh-keygen` and your agent. Undo with `--disable-signing`. Only ever
pass a public key.
