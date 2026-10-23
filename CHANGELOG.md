# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/). Releases are cut by release-please,
which adds new sections above this line from Conventional Commit messages.

## [0.2.0](https://github.com/tyler-jewell/dotfiles/compare/v0.1.0...v0.2.0) (2026-10-23)


### Added

* **bootstrap:** add installer, doctor, uninstall and release downloader ([dfb3c73](https://github.com/tyler-jewell/dotfiles/commit/dfb3c736d5309a8580a4ef635a635d543db91ce3))
* **git:** add layered git config, presets, ignore and attributes ([b49e983](https://github.com/tyler-jewell/dotfiles/commit/b49e98387f06361def8a1d125558b5c93fd4b168))
* **hooks:** add global hooks with profiles that chain to repo hooks ([eb5d52f](https://github.com/tyler-jewell/dotfiles/commit/eb5d52ff68736679e305d79a40b227669bee0e91))
* **sync:** add git-sync, a fast-forward-only branch syncer ([ba616ba](https://github.com/tyler-jewell/dotfiles/commit/ba616bac4437f50e84793fcd91472ab6d6da8252))

## [Unreleased]

## [0.1.0]

### Added
- Global git config layer (`git/presets`, `git/ignore`, `git/attributes`),
  independent of the hook profile and skippable with `bootstrap.sh --no-config`.
- Global hooks that chain to each repo's own hooks, with profiles
  (`dotfiles.profile` = minimal, standard, strict) and per-feature switches
  (`hooks.secretScan`, `hooks.conventionalCommits`, `hooks.branchName`,
  `hooks.branchNamePattern`, `hooks.protectMain`, `hooks.sync`).
- Plaintext `.env` / `.env.*` files are blocked by the secret scan and hidden by
  the global ignore; `*.example`, `*.sample` and `op.refs` are allowed.
- `git sync`: fast-forward-only branch syncer with `--json`, `--dry-run`,
  `--all` (manifest), `--root`, `--prune-merged`, `--hook`.
- `bootstrap.sh`: idempotent installer, `--check` doctor, `--dry-run`,
  `--uninstall` (receipt based, restores backups), layers (`--no-config`,
  `--no-hooks`, `--no-bin`), per-user overlay
  (`~/.config/dotfiles/config`), signing toggle, optional macOS LaunchAgent.
- `install.sh`: optional release downloader that verifies SHA256SUMS first.
- Documentation: threat model, comparison, FAQ, adopting guide, workflow.
- CI (tests on Ubuntu and macOS, shellcheck, shfmt), release automation with
  build provenance.
