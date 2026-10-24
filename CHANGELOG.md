# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the image aims to follow [Semantic Versioning](https://semver.org/) once it is published.

## [Unreleased]

### Added

- `build`, `export`, `export-notes`, `serve` and `watch` take several decks, as slide.ng 2.0 does: `build a.md b.md` writes `/out/a/` and `/out/b/`, and `export a.md b.md` one file per deck. A `.md` value of a flag (`--output talk.md`) is not taken for a deck.
- `serve.mjs` serves a build of several decks: an address gets the `index.html` of the deck folder it is in, `<base>a` goes to `<base>a/`, and the base lists the decks.
- `skills` (`slide-ng skills install`) is passed to slide.ng like `format` and `theme`.

### Changed

- The repository is now `slide-ng/docker` (it was `slide-ng/slide.ng-docker`); links point to the new name.
- The image installs `@slide-ng/core@2.0.0` from npm by default (it was `0.1.0`; the first default, `slide-ng`, was not the package name). `.env.example` and `docker-compose.yml` use the same default; a tarball in `packages/` still works.
- The image installs `@slide-ng/core@2.2.0` by default (it was `2.0.0`). A deck's `slide-ng.config.yaml`, new in slide.ng 2.2, sits next to `slides.md` in `/slides`, so every mode reads it and `watch` rebuilds when it changes.
- `serve.mjs` lets browsers keep the `inline-*.js` files of a slide.ng 2.0 build (the scripts moved out of `index.html`), as it does for the other files with a hash in their name.
- The README says how `--router-mode` and a Content-Security-Policy work with the image.

## [0.1.0] - unreleased

The first version. Nothing is published yet.

### Added

- A `Dockerfile` for a slide.ng image: Node 22, Chromium and fonts, `tini`, a non-root user (uid 1000), with slide.ng installed from a tarball made with `npm pack` or from an npm name.
- An `entrypoint.sh` with the modes `dev`, `build`, `export`, `serve` and `watch`, a password rule for `dev`, and pass-through of any other command.
- A small static file server (`serve.mjs`) for built decks.
- An example `docker-compose.yml` with one profile per mode, and `.env.example`.
- Tests for the entrypoint and the server that run without Docker (`tests/entrypoint.test.sh`), and a GitHub Actions workflow that lints, tests and builds the image without pushing it.
- Repository files for open source hosting: contribution guide, code of conduct, security policy, issue and pull request templates, a commit message hook and its test.

[Unreleased]: https://github.com/slide-ng/docker/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/slide-ng/docker/commits/main
