<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/readme-banner-dark.png">
  <img alt="slide.ng" src="assets/readme-banner-light.png" width="800">
</picture>

# slide.ng docker

A Docker image that runs [slide.ng](https://github.com/slide-ng/slide.ng) decks: live dev server, static build,
PDF/PNG/PPTX export, and a small static server. It follows the idea of Slidev's container repository, with
fewer moving parts: one `Dockerfile`, one `entrypoint.sh`, one static server (`serve.mjs`).

## Status

| Check                                                                                                                                                                                                                                                                                                         | Result                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `shellcheck` on `entrypoint.sh`, the tests and the hook                                                                                                                                                                                                                                                       | passed (shellcheck 0.11.0, 2026-10-24)                                                                                                                                                                                                    |
| `hadolint` on `Dockerfile`                                                                                                                                                                                                                                                                                    | passed (hadolint 2.15.1, one rule off, see `.hadolint.yaml`)                                                                                                                                                                              |
| `bash tests/entrypoint.test.sh` (fake `slide-ng`, real `serve.mjs`)                                                                                                                                                                                                                                           | 75 passed                                                                                                                                                                                                                                 |
| `docker compose config`                                                                                                                                                                                                                                                                                       | parses                                                                                                                                                                                                                                    |
| Image build with `@slide-ng/core` 2.0.0 (tarball in `packages/`)                                                                                                                                                                                                                                              | passed on Docker 29.8.2 on Linux (2026-10-22); `slide-ng --version` prints 2.0.0. The build machine reached Debian only through an HTTPS proxy, so the test copy of the `Dockerfile` sent apt through it; the image is otherwise the same |
| Base image tag exists; Debian `chromium`, `fonts-*`, `tini` install; Chromium starts inside the container                                                                                                                                                                                                     | passed (2026-10-22, Chromium 155)                                                                                                                                                                                                         |
| In the container with 2.0.0: `build --base /talk/`, `build --router-mode hash`, `export --format pdf` with `--shm-size=1g` and the deck mounted `:ro`, `export a.md b.md`, `serve a.md b.md --base /x/` (both decks and the presenter open in Chromium), `watch` (a change is rebuilt), `dev` with a password | passed (2026-10-22)                                                                                                                                                                                                                       |
| Image build with `@slide-ng/core` 2.2.0 from npm (the default)                                                                                                                                                                                                                                                | passed on Docker 29.8.2 on Linux (2026-10-24); `slide-ng --version` prints 2.2.0. Debian again only through an HTTPS proxy, as above                                                                                                      |
| In the container with 2.2.0: `build` and `export --format pdf` of a deck mounted `:ro` with a `slide-ng.config.yaml` (its `title` is the page title), `watch` (a change to that file is rebuilt)                                                                                                              | passed (2026-10-24)                                                                                                                                                                                                                       |
| `docker compose --profile build run --rm build` (`cap_drop: [ALL]`, `no-new-privileges`)                                                                                                                                                                                                                      | passed (2026-10-22)                                                                                                                                                                                                                       |
| `read_only: true` of the `serve` and `watch` profiles                                                                                                                                                                                                                                                         | `serve` passed with the same settings given to `docker run` (`--read-only --tmpfs /tmp:exec,mode=1777 --cap-drop ALL`, 2026-10-22); `watch` NOT VERIFIED                                                                                  |
| GitHub Actions workflow runs                                                                                                                                                                                                                                                                                  | NOT VERIFIED (YAML parses only)                                                                                                                                                                                                           |

The commands marked NOT VERIFIED above are untested. An earlier check on Docker Desktop for Mac (2026-10-16) found that a deck mounted read-write failed there, so mount it `:ro` on a Mac.

## Build the image

By default the image installs `@slide-ng/core@2.2.0` from npm (a pinned release, so builds are reproducible). The build
argument `SLIDE_NG_SOURCE` picks another version (anything `npm install` accepts, such as `@slide-ng/core@latest`) or a
tarball inside the build context, for example one packed from a slide.ng checkout:

```sh
docker build -t slide-ng .
docker build --build-arg SLIDE_NG_SOURCE=@slide-ng/core@latest -t slide-ng .
npm pack /path/to/slide.ng --pack-destination packages
docker build --build-arg SLIDE_NG_SOURCE=packages/slide-ng-core-2.2.0.tgz -t slide-ng .
```

Other build arguments: `NODE_VERSION` (default `22.23.3`; slide.ng needs 22.22.3 or newer) and `EXTRA_FONTS`
(extra Debian font packages, for example `fonts-noto-cjk`).

## Run

`docker run [options] slide-ng <mode> [flags]`. Flags after the mode go to slide.ng unchanged. The deck is
`/slides/slides.md` (another name: `SLIDES_FILE=my.md`); a `slide-ng.config.yaml` next to it is read too. Modes:
`dev` (default, port 4230), `build`, `export`, `export-notes`, `serve` and `watch` (port 8080), `help`. Any other first word is run as a command. Run
`help` for the variables; `docker-compose.yml` has one profile per mode (copy `.env.example` to `.env`).

```sh
# dev: live server, password protected (random one in the log if you set none), no HTTPS
docker run --rm -it -p 127.0.0.1:4230:4230 -e SLIDES_PASSWORD='a-long-password' -v "$PWD:/slides" slide-ng dev

# build: static site into ./out (create it first)
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/slides" -v "$PWD/out:/out" slide-ng build --base /talk/ --download

# export: pdf, png, pptx or md into ./out
docker run --rm --user "$(id -u):$(id -g)" --shm-size=1g -v "$PWD:/slides" -v "$PWD/out:/out" slide-ng export --format pdf

# serve: build, then serve; watch also rebuilds on change
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD:/slides" slide-ng serve
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD:/slides" slide-ng watch

# several decks: /slides/a.md and /slides/b.md into ./out/a/ and ./out/b/ (served under /a/ and /b/)
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/slides" -v "$PWD/out:/out" slide-ng build a.md b.md
```

- `dev` saves edits into `/slides`, so it cannot be mounted `:ro`. Open the "private slide show" address it prints and use `localhost` or an IP address as the host.
- `build`, `export`, `export-notes`, `serve` and `watch` take several `.md` files after the mode, as `slide-ng` does. `build a.md b.md` writes `/out/a/` and `/out/b/`, each served under `<base>a/` and `<base>b/`; `export a.md b.md` writes one file per deck. `serve` and `watch` serve each deck in its folder and list the decks at the base. `dev` runs one deck.
- `--router-mode hash` (or `memory`) for `build`, `serve` and `watch` is passed to slide.ng like any other flag; a hash or memory build needs no help from the web server.
- `serve --dist /site` serves a folder you built earlier. `serve.mjs` has no compression and no TLS; for a public site put the `build` output behind a real web server.
- `serve.mjs` sends no `Content-Security-Policy`. A slide.ng 2.0 build keeps no inline script in `index.html` (they are `inline-*.js` files), so the web server in front of it can send a strict policy; the one slide.ng tested is in its [HOSTING.md](https://github.com/slide-ng/slide.ng/blob/main/docs/HOSTING.md#content-security-policy).
- The container runs as `node` (uid 1000). On Linux pass `--user "$(id -u):$(id -g)"` and create `out` yourself, or it belongs to root. Docker Desktop maps ownership for you.

### Chromium and the sandbox

The image sets `SLIDE_NG_NO_SANDBOX=1`, so slide.ng starts Chromium with `--no-sandbox` (a normal container cannot
run Chromium's own sandbox). No `--privileged`, `SYS_ADMIN` or custom seccomp profile is needed. The image runs as a
non-root user, and the compose file drops all capabilities and sets `no-new-privileges`.

- Use `--shm-size=1g` for export. Docker's default 64 MB makes Chromium crash on big slides.
- Export only decks you trust. Add fonts with `EXTRA_FONTS`; a missing font silently falls back.

## Development

```sh
bash tests/entrypoint.test.sh      # no Docker needed; needs bash, node 22, curl
```

The tests use a fake `slide-ng`, so they cannot catch problems inside the image. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Changes follow the [Code of Conduct](CODE_OF_CONDUCT.md); security reports go through [SECURITY.md](SECURITY.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

MIT License © 2026 [Erkam Yaman](https://github.com/erkamyaman) ([LICENSE](LICENSE)).

## Credits and disclaimer

The idea comes from [slidevjs/container](https://github.com/slidevjs/container) (MIT) for [Slidev](https://github.com/slidevjs/slidev). No code from those projects is copied here.

slide.ng is an independent open-source project. It is not affiliated with or endorsed by the Angular team or Google, or by Slidev. Angular is a trademark of Google LLC.

Related repositories: [slide.ng](https://github.com/slide-ng/slide.ng), [themes](https://github.com/slide-ng/themes), [starter](https://github.com/slide-ng/starter), [docs](https://github.com/slide-ng/docs), [vscode](https://github.com/slide-ng/vscode-extension). These addresses are placeholders until the repositories are published.

## Maintainers

<!-- prettier-ignore-start -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/erkamyaman"><img src="https://avatars.githubusercontent.com/u/88717125?v=4&s=100" width="100px;" alt="Erkam Yaman"/><br /><sub><b>Erkam Yaman</b></sub></a><br /><sub>Maintainer</sub></td>
    </tr>
  </tbody>
</table>
<!-- prettier-ignore-end -->

## Contributors

Thanks to everyone who has helped. This project follows the [all-contributors](https://allcontributors.org) specification. Contributions of any kind welcome!

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/erkamyaman"><img src="https://avatars.githubusercontent.com/u/88717125?v=4?s=100" width="100px;" alt="Erkam Yaman"/><br /><sub><b>Erkam Yaman</b></sub></a><br /><a href="https://github.com/slide-ng/docker/commits?author=erkamyaman" title="Code">💻</a> <a href="https://github.com/slide-ng/docker/commits?author=erkamyaman" title="Documentation">📖</a> <a href="#infra-erkamyaman" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#maintenance-erkamyaman" title="Maintenance">🚧</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

## Sponsors

The slide.ng Docker image is free and open source. If it helps your work, please consider sponsoring it. Your support keeps development going.

<p>
  <a href="https://github.com/sponsors/erkamyaman"><img src="https://img.shields.io/badge/Sponsor-%E2%9D%A4-db61a2?logo=githubsponsors&logoColor=white" alt="Sponsor on GitHub" /></a>
</p>
