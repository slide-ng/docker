# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the image aims to follow [Semantic Versioning](https://semver.org/) once it is published.

## [Unreleased]

## [0.1.0] - unreleased

The first version. Nothing is published yet.

### Added

- A `Dockerfile` for a slide.ng image: Node 22, Chromium and fonts, `tini`, a non-root user (uid 1000), with slide.ng installed from a tarball made with `npm pack` or from an npm name.
- An `entrypoint.sh` with the modes `dev`, `build`, `export`, `serve` and `watch`, a password rule for `dev`, and pass-through of any other command.
- A small static file server (`serve.mjs`) for built decks.
- An example `docker-compose.yml` with one profile per mode, and `.env.example`.
- Tests for the entrypoint and the server that run without Docker (`tests/entrypoint.test.sh`), and a GitHub Actions workflow that lints, tests and builds the image without pushing it.
- Repository files for open source hosting: contribution guide, code of conduct, security policy, issue and pull request templates, a commit message hook and its test.

[Unreleased]: https://github.com/slide-ng/slide.ng-docker/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/slide-ng/slide.ng-docker/commits/main
