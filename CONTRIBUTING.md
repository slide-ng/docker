# Contributing

Thanks for helping. This repository is small on purpose: one `Dockerfile`, one entrypoint script,
one tiny static server. Please keep it readable.

## Ground rules

- Shell: bash, `set -euo pipefail`, must pass `shellcheck`.
- Dockerfile: must pass `hadolint` (see `.hadolint.yaml` for the one rule we turn off, and why).
- No new runtime dependencies in the image unless there is a clear need. The static server uses only Node.
- Do not change how slide.ng behaves here. Flags are passed through; fixes to slide.ng belong in the slide.ng repository.
- Keep the security defaults: non-root user, password for `dev`, compose ports on `127.0.0.1`.

## Run the checks

```sh
bash tests/entrypoint.test.sh          # needs bash, node 22, curl; no Docker
shellcheck entrypoint.sh tests/entrypoint.test.sh
hadolint Dockerfile
```

If you have Docker, also build and run the image (see the README) and say so in the pull request.
A change that was not run in a real container should say that plainly.

## Commits and pull requests

- Small commits with a short subject in the imperative ("Add watch mode").
- Say what you ran. Do not claim a check you did not run.
- Update the README when you change a variable, a port or a mode.

By contributing you agree that your work is licensed under the MIT license of this repository.
