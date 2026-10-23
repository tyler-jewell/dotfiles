<!-- PR title must be a Conventional Commit: type(scope): summary. It becomes the squash commit title. -->

## What

<!-- One or two sentences: what changes. -->

## Why

<!-- The problem or goal. Link the issue: Closes #123 -->

## How tested

<!-- Commands run (e.g. bash tests/run.sh), output observed, or why no test applies. -->

## Checklist

- [ ] Branch is `type/issue-slug` and the PR title is a Conventional Commit
- [ ] Commits are signed off (`git commit -s`)
- [ ] Tests added or updated; `bash tests/run.sh` passes (also on macOS `/bin/bash` 3.2 if relevant)
- [ ] No personal, host or org specific data; no secrets; no new network access or prompts
- [ ] Docs updated if behaviour or flags changed
