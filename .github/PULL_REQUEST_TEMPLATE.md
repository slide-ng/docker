<!-- Title the pull request like a commit: type(scope): summary. See the "Commit messages" section of CONTRIBUTING.md -->

## What and why

<!-- What does this change, and why is it needed? Link an issue with "Fixes #123". -->

## How I checked it

<!-- The commands you ran. Say plainly if you did not build or run the image in a real container. -->

## Checklist

- [ ] `bash tests/entrypoint.test.sh` and `bash tests/commit-msg.test.sh` pass.
- [ ] `shellcheck -x` and `hadolint` pass, or I say here which one I could not run.
- [ ] I built and ran the image, or I say here that I did not.
- [ ] I updated the README for a changed variable, port or mode.
- [ ] I kept the security defaults: non-root user, a password for `dev`, compose ports on `127.0.0.1`.
- [ ] I agree that my contribution is under the MIT license.
