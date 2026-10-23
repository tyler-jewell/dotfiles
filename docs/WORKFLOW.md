# Workflow

The conventions the `strict` profile helps you follow. They are defaults, not
dogma: every piece can be changed or turned off (see [GIT-CONFIG.md](GIT-CONFIG.md)).

1. **Branch** from an up-to-date `main`: `type/issue-slug`, e.g.
   `feat/123-git-sync`. `type` is one of `feat fix docs style refactor perf test
   build ci chore revert`; the issue number is optional; the slug is lower-case
   `a-z0-9-`. Enforced by `hooks.branchName` (pattern: `hooks.branchNamePattern`).
2. **Commit** with [Conventional Commits](https://www.conventionalcommits.org/):
   `type(scope)!: subject`, small and reviewable. Enforced by
   `hooks.conventionalCommits`.
3. **Push** the branch (`push.autoSetupRemote` sets the upstream). Direct pushes
   to `main`/`master` are refused locally by `hooks.protectMain`
   (`GIT_ALLOW_MAIN_PUSH=1` allows one).
4. **Open a PR** whose title is itself a Conventional Commit (it becomes the
   squash commit message).
5. **Squash merge**, linear history, delete the branch. Then
   `git sync --prune-merged` (or `--prune-squashed`) tidies local branches; a
   bundle backup of every deleted tip is written first.
6. **Secrets** are referenced, never committed: `*.example` templates in git,
   real values injected at runtime by your secret manager.

Optional: `hooks.issueFooter = true` appends `Refs: #N` when the branch is
named `type/N-slug`.

Local hooks mirror, but are not a substitute for, server-side rules (required
PR, linear history, required checks). Bypass when you really must:
`git commit --no-verify`, `git push --no-verify`.
