# Adopting gradually

You do not have to take everything. A sensible path, each step reversible.

## 1. Look before you touch

```sh
git clone https://github.com/tyler-jewell/dotfiles ~/dotfiles && cd ~/dotfiles
./bootstrap.sh --dry-run          # prints every link it would make
less git/hooks/pre-commit          # read what will run in every repo
bash tests/run.sh                  # optional: run the tests in a sandbox HOME
```

## 2. Start with one layer

| You want | Command |
|---|---|
| Only the safety hooks | `./bootstrap.sh --no-config --no-bin` |
| Only the git defaults | `./bootstrap.sh --no-hooks --no-bin` |
| Everything | `./bootstrap.sh` |

Layers are independent. Hooks-only installs do not set `pull.ff` or anything
else; config-only installs set no `core.hooksPath`. To add a skipped layer
later, run bootstrap again without the flag. To drop a layer, uninstall and
reinstall with the flag (`--uninstall` first), or delete its links by hand.

## 3. Start with the `minimal` profile

```ini
# ~/.config/dotfiles/config
[dotfiles]
	profile = minimal
```

Only the secret scan runs. When it has been quiet for a while, move up:
`standard` adds the Conventional Commits check and background fetch; `strict`
adds branch-name and main-branch protection. Downgrading is the same one-line
edit; nothing is cached or migrated. Pin single features whatever the profile:
`hooks.branchName = false`.

## 4. Per-repo exemptions

Not every repo wants these rules. Pick the narrowest tool:

```sh
git config --local hooks.exempt true        # this repo: no checks, no sync
git config --local hooks.branchName false   # this repo: only that feature off
```

Org-wide, in your overlay:

```ini
[hooks]
	exemptOrigins = *github.com/acme-corp/*
	exemptOrigins = *gitlab.example.com/legacy/*
```

An exempt repo's own hooks still run.

## 5. Coexisting with lefthook, husky, pre-commit

- **Hooks in `.git/hooks`** (pre-commit installs there, old lefthook): keep
  working. Our hooks run their check, then run the repo hook.
- **A local `core.hooksPath`** (husky sets `.husky/_`, newer lefthook can set
  one): git prefers the local value over the global one, so ours do not run in
  that repo and nothing double-runs. If you want both, call ours from the repo
  hook, or leave the repo to its own tooling.
- **`pre-commit install` refuses to run** while a global `core.hooksPath` is
  set. Use `pre-commit install --install-hooks` after
  `git config --local core.hooksPath .git/hooks`, or run
  `git config --local --unset core.hooksPath` and set the exemption instead.
- **lefthook install**: `lefthook install --force` is the usual answer.

Rule of thumb: the project's tooling owns project-specific checks, this owns
the personal baseline. Where they overlap (for example commit-message checks),
disable ours for that repo with `hooks.conventionalCommits=false`.

## 6. Add `git sync` when you are ready

`hooks.sync` only fetches. For the whole machine, write a manifest
(`~/.config/dotfiles/repos.txt`, format in
[manifest/repos.example.txt](../manifest/repos.example.txt)) and run
`git sync --all`, or use `git sync --root ~/code`. On macOS,
`./bootstrap.sh --install-launchd` runs it every 15 minutes.

## 7. Secrets

Plaintext `.env` files are always blocked by the secret scan. Move to
references: commit an `op.refs` file with `op://example-vault/example-item/field`
lines and run commands through `op run --env-file=op.refs -- <cmd>` (1Password
is one option; any manager that injects at runtime fits). The companion tool
[`op-doctor`](https://github.com/tyler-jewell/op-doctor) can check that your
references resolve.

## Backing out

`./bootstrap.sh --uninstall --dry-run`, then without `--dry-run`. Your overlay
is removed only if you never edited it.
