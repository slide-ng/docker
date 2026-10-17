# Contributing to slide.ng docker
Thanks for helping. This repository is small on purpose: one `Dockerfile`, one entrypoint script,
one tiny static server. Please keep it readable.

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). Report security problems privately,
as [SECURITY.md](SECURITY.md) describes. By contributing you agree that your work is licensed under the
[MIT license](LICENSE) of this project.

## Set up

There is no npm project here. You need bash, Node.js 22 (the tests use it for `serve.mjs`), curl and,
to build the image, Docker. `shellcheck` and `hadolint` are optional locally; CI runs both.

```sh
git clone https://github.com/slide-ng/docker.git
cd docker
git config core.hooksPath .githooks     # optional: warns about commit messages
git config commit.template .gitmessage  # optional: shows the message format in your editor
```

The `commit-msg` hook only warns, it never blocks a commit.

## Ground rules

- Shell: bash, `set -euo pipefail`, must pass `shellcheck`.
- Dockerfile: must pass `hadolint` (see `.hadolint.yaml` for the one rule we turn off, and why).
- No new runtime dependencies in the image unless there is a clear need. The static server uses only Node.
- Do not change how slide.ng behaves here. Flags are passed through; fixes to slide.ng belong in the slide.ng repository.
- Keep the security defaults: non-root user, password for `dev`, compose ports on `127.0.0.1`.
- Small files and plain comments. `.editorconfig` has the whitespace rules.

## Run the checks

```sh
bash tests/entrypoint.test.sh          # needs bash, node 22, curl; no Docker
bash tests/commit-msg.test.sh          # the commit message hook
shellcheck -x entrypoint.sh tests/*.sh .githooks/commit-msg
hadolint Dockerfile
```

If you have Docker, also build and run the image (see the README) and say so in the pull request.
A change that was not run in a real container should say that plainly.

## Commit messages

`type(scope): summary`, imperative, lower case, no period, 72 characters at most, no trailer lines.
An optional body, after a blank line, says why.

- Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `style`, `build`, `ci`, `chore`, `revert`.
- Scopes: `entrypoint`, `dockerfile`, `serve`, `compose`, `tests`, `docs`, `ci`. Leave the scope out when a change spans several parts.

Pull requests are squash merged, so the pull request title must follow the same form.

## Changing the entrypoint

1. Edit `entrypoint.sh`. A new mode needs a `mode_<name>` function, a line in the header comment (which `help` prints), an entry in the `case` in `main`, and a row in the modes table of the README.
2. Add the case to `tests/entrypoint.test.sh`. The test uses a fake `slide-ng` that records its arguments, so it needs no Docker.
3. A new environment variable goes into the header comment, `.env.example` if it is for compose, and the README reference.
4. Run `bash tests/entrypoint.test.sh` and `shellcheck -x entrypoint.sh tests/entrypoint.test.sh`.

## Pull requests

- Keep a pull request to one change. Fill in the template.
- Say what you ran. Do not claim a check you did not run.
- Update the README when you change a variable, a port or a mode.
- Open an issue first for large changes, so we can agree on the approach.

## Recognising contributions

Everyone who helps is listed in the Contributors section of the README, whatever the kind of help: code, docs, design, review or triage. To add someone, comment `@all-contributors please add @user for code` on an issue or pull request (use another type such as `doc`, `review` or `bug` when it fits). The bot opens a pull request that updates `.all-contributorsrc` and the README.
