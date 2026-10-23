# Releasing

Releases are driven by [release-please](https://github.com/googleapis/release-please).

1. Merge Conventional Commit PRs into `main`. `release.yml` keeps a "release PR"
   open that bumps `VERSION`, `.release-please-manifest.json` and `CHANGELOG.md`.
2. Merge the release PR. release-please tags `vX.Y.Z` and creates the GitHub release.
3. The same workflow then builds `dotfiles-X.Y.Z.tar.gz` with
   `scripts/make-release.sh` (`git archive` of the tag), writes `SHA256SUMS`,
   creates build provenance with `actions/attest-build-provenance`, and uploads
   both files to the release.

`VERSION` is the single source of truth for `--version` (`bootstrap.sh`,
`git-sync`); its first field is the version, the rest is a release-please marker
comment. Verify a download:

```sh
sha256sum -c SHA256SUMS
gh attestation verify dotfiles-X.Y.Z.tar.gz --repo tyler-jewell/dotfiles
```

First release: the manifest starts at `0.1.0`. The first release PR will bump
from there; to publish `0.1.0` itself, create the `v0.1.0` tag and release
manually once, then let release-please take over.
