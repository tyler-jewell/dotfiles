# FAQ

**Will this break my existing hooks (husky, lefthook, hand-written)?**
No: global hooks chain to `.git/hooks/<name>` after their own checks. If a tool
sets a *local* `core.hooksPath`, git uses that and ours do not run in that repo.
See [ADOPTING.md](ADOPTING.md).

**How do I turn it off right now?**
`export GIT_HOOKS_EXEMPT=1` for the shell, `--no-verify` for one command,
`git config --local hooks.exempt true` for one repo, `./bootstrap.sh --uninstall`
for everything.

**Which profile should I choose?**
Start with `minimal` (only the secret scan). `standard` (default) adds
Conventional Commits and background fetch. `strict` adds branch names and
main-branch protection, which suits PR-based workflows.

**The commit-msg check rejects my message.**
Format: `type(scope)!: subject`, types `feat fix docs style refactor perf test
build ci chore revert`, header up to 100 characters. `Merge`, `Revert`,
`fixup!`, `squash!` are accepted. Disable with `hooks.conventionalCommits=false`.

**The branch-name check rejects my branch.**
Default `type/[issue-]slug`, for example `feat/123-login`. Change it:
`git config hooks.branchNamePattern '^(feat|fix)/[a-z0-9-]+$'` (extended
regex), or turn it off: `git config hooks.branchName false`.

**Why was my `.env` file blocked? How do I use secrets?**
Plaintext env files are blocked on purpose (and hidden by the global ignore).
Commit a `*.example` template, and inject real values at runtime from your
secret manager. One option: a committed `op.refs` file with `op://` references
run through `op run --env-file=op.refs -- <cmd>`.

**The secret scanner flagged a false positive.**
Put `secret-scan:allow` on that line, or commit with `--no-verify` once. Install
`gitleaks` for a bigger rule set (`DOTFILES_SECRET_SCANNER=builtin` skips it).

**`git sync` says a branch is `behind-skipped-dirty`.**
It is behind its upstream but your working tree has changes (or a merge/rebase
is in progress). Commit or stash, then run it again. It never touches dirty trees.

**Does the background sync change my checked-out branch?**
No. The hook trigger only fetches (and fast-forwards *other*, non-checked-out
branches). Set `sync.hookUpdateCurrent=true` to let it fast-forward the current
branch as well.

**Where do my name, email and signing key go?**
Your overlay, `~/.config/dotfiles/config` (`--name`, `--email`,
`--enable-signing`). It is never overwritten and is included last.

**I have `~/.gitconfig`. Does that matter?**
Git reads `~/.config/git/config` first and `~/.gitconfig` after it, so values in
`~/.gitconfig` win over both our presets and your overlay. `--check` warns.

**Does it work with `XDG_CONFIG_HOME`?**
The config layers and overlay follow it. `core.hooksPath` is written as
`~/.config/git/hooks`, so hooks need the default location (`--check` warns).

**Linux?**
Yes (bash 4/5, GNU tools). Windows only through WSL.

**How do I uninstall?**
`./bootstrap.sh --uninstall` (`--dry-run` first). It removes only what it
linked or created, restores backups, and keeps an overlay you edited.

**Is anything sent anywhere?**
No. See [THREAT-MODEL.md](THREAT-MODEL.md).
