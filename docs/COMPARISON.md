# Comparison and when not to use this

An honest map of the neighbourhood. None of these are mutually exclusive.

| | This project | pre-commit | lefthook | husky | plain `core.hooksPath` | git-town / git-up style tools |
|---|---|---|---|---|---|---|
| Scope | **machine-wide**, all repos | per repo (config file) | per repo | per repo (npm) | machine-wide or per repo | per repo workflow |
| Team-shared and versioned in the repo | no (your machine) | **yes** | **yes** | **yes** | no | n/a |
| Linters/formatters for the project | no | **huge ecosystem** | yes, parallel | yes | DIY | no |
| Enforces policy on contributors who do not install it | no | CI can | CI can | CI can | no | no |
| Works in repos you do not control | **yes** | needs a config in the repo | needs a config | needs package.json | yes | yes |
| Chains to a repo's own hooks | **yes** | n/a | n/a | n/a | no (replaces `.git/hooks`) | n/a |
| Syncs branches | fast-forward only, never rewrites | no | no | no | no | rebases/merges/stacks (git-town), `git up`-style pull-all |
| Dependencies | bash, git | Python | one binary | Node | none | Go binary / Ruby |

## Notes by neighbour

**pre-commit / lefthook / husky** are the right tools to put checks *in a
project* so every contributor and CI run the same thing. This project does not
replace them. It covers what they cannot: personal, cross-repo safety nets
(secret scan, commit-message style) in repos that have no config of their own.
Coexistence is covered in [ADOPTING.md](ADOPTING.md): a repo-local
`core.hooksPath` (what husky and lefthook may set) overrides the global one, so
the two never double-run.

**A bare global `core.hooksPath`** is the mechanism we use, with two additions:
chaining so repo hooks keep working (the bare approach silently disables
every repo's `.git/hooks`), and switches so you can turn pieces off per repo.

**git-town, git-up and friends** manage workflows: stacked branches, ship,
sync with merge or rebase. `git sync` here is deliberately tiny and
conservative: it fast-forwards branches that can be fast-forwarded and reports
everything else. If you want your tool to rebase or merge for you, use theirs.

## When NOT to use this

- You want checks that **every contributor** must pass: put them in the repo
  (pre-commit/lefthook/husky) and in CI. A local hook is a convenience, not a
  security boundary.
- You cannot or will not review a few hundred lines of shell that run on every
  commit. Pick a tool from a vendor you already trust, or read the code first.
- You work mostly on Windows without WSL.
- Your employer manages `core.hooksPath` or git config centrally (it may be
  overridden or conflict; use only `--no-hooks` for the git presets, or skip).
- You need a different branch or commit policy than configurable here and
  `hooks.branchNamePattern` cannot express it.
