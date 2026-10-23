# Security policy

## Reporting a vulnerability

Please report privately through GitHub: **Security tab > Report a vulnerability**
(private vulnerability reporting). Do not open a public issue or pull request.
Expect an acknowledgement within a few days. Never include live secrets in a
report; redact them.

Relevant areas: anything the global hooks, `bootstrap.sh`, `git-sync` or
`install.sh` could do that you would not expect (see
[docs/THREAT-MODEL.md](docs/THREAT-MODEL.md)): writing outside `$HOME`,
following a symlink or archive entry to an unintended path, running attacker
supplied input as code, leaking a scanned secret into output, or weakening
checksum verification in `install.sh`.

## Supported versions

Only the latest release and `main` receive fixes.

## Secrets

This repository must never contain secrets. If you spot one, report it as above
and rotate the credential first. The pre-commit secret scan is a safety net,
not a guarantee; `--no-verify` bypasses it by design.
