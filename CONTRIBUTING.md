# Contributing

Thanks for helping. Small, focused pull requests are easiest to review.

## Ground rules

- **Conventional Commits** for every commit and for the PR title (it becomes the
  squash commit): `type(scope)!: subject`, types `feat fix docs style refactor
  perf test build ci chore revert`.
- **DCO sign-off** on every commit: `git commit -s` adds
  `Signed-off-by: Your Name <you@example.com>`. By signing off you certify the
  [Developer Certificate of Origin](DCO.md). Forgot?
  `git rebase --signoff origin/main`.
- **Branches** are named `type/issue-slug`, e.g. `fix/42-uninstall-backup`.
- **Tests are required.** Behaviour changes and bug fixes come with tests in
  `tests/`; a new hook switch needs cases in `tests/test_profiles.sh`.
- **No personal or host-specific data** in code, docs or tests: use `acme-corp`,
  `example.com`, `example-vault`. No telemetry, no extra network access, no
  prompts, every command keeps `--json` and documented exit codes
  (see [AGENTS.md](AGENTS.md)).

## Running the checks

```sh
bash tests/run.sh              # everything (bash + git; jq optional)
bash tests/run.sh profiles     # files whose name contains "profiles"
shellcheck -x $(git ls-files | xargs grep -l '^#!.*bash')   # lint
shfmt -d     $(git ls-files | xargs grep -l '^#!.*bash')    # format check (2-space, see .editorconfig)
```

Tests run in a throwaway `HOME`; they never touch your real configuration.
Scripts must stay compatible with macOS `/bin/bash` 3.2 and Linux bash. Run the
suite with `/bin/bash tests/run.sh` on a Mac.

## Pull request flow

1. Open or pick an issue; branch from `main`.
2. Make the change, add tests, update docs and `CHANGELOG.md` only if you are
   not relying on release-please (it writes the changelog from commit messages).
3. Open the PR; fill in the template. CI runs tests on Ubuntu and macOS,
   shellcheck, shfmt, the DCO check and a secret scan.
4. Maintainers squash-merge once checks pass.

## Reporting bugs and security issues

Bugs: use the issue templates. Vulnerabilities: see [SECURITY.md](SECURITY.md),
never a public issue.

By contributing you agree your work is licensed under the Apache License 2.0.
See the [Code of Conduct](CODE_OF_CONDUCT.md).
