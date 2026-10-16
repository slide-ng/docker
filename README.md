# slide.ng-docker

A Docker image that runs [slide.ng](https://github.com/slide-ng/slide.ng) decks: live dev server, static build,
PDF/PNG/PPTX export, and a tiny static server. It follows the idea of Slidev's container repository, with
fewer moving parts: one `Dockerfile`, one readable `entrypoint.sh`, one 100-line static server (`serve.mjs`).

## Status

| Check | Result |
| --- | --- |
| `shellcheck` on `entrypoint.sh` and the test | passed |
| `hadolint` on `Dockerfile` | passed (one rule off, see `.hadolint.yaml`) |
| `bash tests/entrypoint.test.sh` (fake `slide-ng`, real `serve.mjs`) | 59 passed |
| `entrypoint.sh` against the real slide.ng core, outside Docker (`build --base /talk/`, `serve --dist`, `export --format pdf`, `dev`) | worked |
| `docker compose config` | parses |
| **Image build and run** | **NOT VERIFIED.** The sandbox this was written in has the Docker client but no Docker daemon, so `docker build` and `docker run` were never executed. |
| Base image tag `node:22.23.3-bookworm-slim` exists on Docker Hub | NOT VERIFIED (no network access to the registry) |
| Debian `chromium`, `fonts-*`, `tini` packages install; Chromium starts inside the container | NOT VERIFIED |
| Export from inside the container (`--shm-size`, `--cap-drop ALL`, `--read-only`, any `--user`) | NOT VERIFIED |
| GitHub Actions workflow runs | NOT VERIFIED (YAML parses only) |

Until someone has built the image once, treat every `docker` command below as untested.

## Getting slide.ng into the image

slide.ng is not on npm yet. The image installs it from the build argument `SLIDE_NG_SOURCE`:

- a **tarball** inside the build context, for example `packages/slide-ng-0.0.0.tgz`, or
- anything `npm install` accepts: `slide-ng`, `slide-ng@1.2.3` (works once it is published).

Make a tarball from a slide.ng checkout:

```sh
npm pack /path/to/slide.ng --pack-destination packages
```

`"private": true` in slide.ng's `package.json` does not stop `npm pack` (it only stops `npm publish`), and the
`files` list contains everything the CLI needs (`bin`, `scripts`, `src`, `public`, `template`, the Angular and
TypeScript settings, `docs`). Packing the current checkout gave `slide-ng-0.0.0.tgz`, 478 files, 1.7 MB. Notes:

- Dependencies are not in the tarball; `npm install` fetches them from the registry while the image builds.
- A checkout that has been used for development also packs `src/slides/generated/`. slide.ng ignores it when it builds a deck, so it is harmless.
- If you ever add `.npmignore` rules or change `files`, pack once and check with `tar tzf`.
- The tarball must be inside this repository's build context (`packages/`); an absolute path outside it cannot be copied in. `packages/*.tgz` is git-ignored.

Build:

```sh
docker build --build-arg SLIDE_NG_SOURCE=packages/slide-ng-0.0.0.tgz -t slide-ng .
```

Other build arguments: `NODE_VERSION` (default `22.23.3`; slide.ng needs 22.22.3 or newer) and `EXTRA_FONTS`
(extra Debian font packages for export, for example `--build-arg EXTRA_FONTS=fonts-noto-cjk`).

## Modes

`docker run [options] slide-ng <mode> [flags]`. Flags after the mode go to slide.ng unchanged
(see the slide.ng README for all of them). The deck is `/slides/slides.md` (set another name with `SLIDES_FILE=my.md`).

| Mode | What it does | Port | Mounts |
| --- | --- | --- | --- |
| `dev` (default) | live dev server, listens on `0.0.0.0`, password protected | 4230 | `/slides` read-write |
| `build` | static site written to `/out` | | `/slides`, `/out` |
| `export` | PDF (default), PNG, PPTX or Markdown written to `/out` | | `/slides`, `/out` |
| `export-notes` | speaker notes as PDF into `/out` | | `/slides`, `/out` |
| `serve` | builds the deck, then serves it (Node, no nginx) | 8080 | `/slides` |
| `watch` | like `serve`, and rebuilds when something in `/slides` changes | 8080 | `/slides` |
| `help` | prints the modes and variables | | |

Any other first word is run as a command: `docker run slide-ng format`, `... create .`, `... bash`.

### dev

```sh
docker run --rm -it -p 127.0.0.1:4230:4230 -e SLIDES_PASSWORD='a-long-password' \
  -v "$PWD:/slides" slide-ng dev
```

Open the "private slide show" address that slide.ng prints (it has `?password=...`). The container prints
addresses of its own network; replace the host part with `localhost` or your machine's address.

How the password works (these are slide.ng's `--remote` rules, kept as they are):

- The entrypoint runs `slide-ng dev --bind 0.0.0.0 --remote=<password>`. The bind is needed, or a published port reaches nothing.
- Password source, in order: `SLIDES_PASSWORD`, then the first line of the file in `SLIDES_PASSWORD_FILE` (a Docker secret), then a **random password** that is made and printed in the log.
- `SLIDES_NO_PASSWORD=1` runs plain `--remote`. slide.ng then prints a warning: anyone who can reach the port can open the deck and drive the presenter.
- Even without a password slide.ng still checks the Host header, Origin and a session token on every request. Because of the Host check, open the deck by `localhost`, an IP address, or the container's host name. A DNS name that points to your machine will be refused by the companion server.
- There is no HTTPS: the password crosses the network in clear text. Publish the port on `127.0.0.1` (as above) unless you trust the network, and use a reverse proxy with TLS otherwise.
- If you pass `--remote` or `--bind` yourself, yours is used and no password is made. The password is visible to `ps` inside the container.
- Dev mode saves edits and drawings into `/slides`, so it cannot be mounted `:ro`.

### build

```sh
mkdir -p out
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/slides" -v "$PWD/out:/out" \
  slide-ng build --base /talk/ --download
```

`--download` and an automatic Open Graph picture need Chromium; both are in the image. `--out` is refused: the output
folder is always `/out`. As in slide.ng, `/out` is only emptied when it is empty or holds an earlier build (it has a
`.slide-ng-build` file); a folder with other files is refused and left alone. Existing content is replaced
only after the new build succeeded.

### export

```sh
docker run --rm --user "$(id -u):$(id -g)" --shm-size=1g -v "$PWD:/slides" -v "$PWD/out:/out" \
  slide-ng export --format pdf --with-clicks
docker run --rm --user "$(id -u):$(id -g)" --shm-size=1g -v "$PWD:/slides" -v "$PWD/out:/out" \
  slide-ng export --format pptx --output talk.pptx
```

The file is written to `/out` (`--output` is relative to it). Other flags: `--range`, `--dark`, `--scale`, `--timeout`, ... as in slide.ng.

### serve

```sh
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD:/slides" slide-ng serve
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD:/slides" slide-ng serve --base /talk/    # served at /talk/
# serve a folder you built earlier, no build:
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD/out:/site:ro" slide-ng serve --dist /site
```

`serve.mjs` answers unknown deck addresses (`/3`, `/presenter/1`) with `index.html`, supports Range requests for video, refuses dot files and
anything outside the folder, and sends `Cache-Control: immutable` for hashed files. It does not compress and has no TLS; for a public site
use the static `build` output behind a real web server (see slide.ng's `docs/HOSTING.md`).

### watch

```sh
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD:/slides" slide-ng watch
```

Builds once, serves, then checks `/slides` every `WATCH_INTERVAL` seconds (default 2) and rebuilds after a change. The new build replaces the
old one in one step; if a rebuild fails, the last good version keeps being served and the error is in the log. Reload the page to see the change
(this is a rebuild loop, not the live dev server; use `dev` for live updates).

### docker compose

`docker-compose.yml` has one profile per mode. Copy `.env.example` to `.env`, then for example
`docker compose --profile dev up` or `docker compose --profile export run --rm export`.

## Reference

| Variable | Default | Used by |
| --- | --- | --- |
| `SLIDES_FILE` | `slides.md` | all modes |
| `SLIDES_PASSWORD`, `SLIDES_PASSWORD_FILE`, `SLIDES_NO_PASSWORD` | random password | dev |
| `PORT` | `4230` (dev), `8080` (serve, watch) | dev, serve, watch |
| `WATCH_INTERVAL` | `2` | watch |
| `CHROME_PATH` | `/usr/bin/chromium` | export, build `--download` |

Volumes: `/slides` (the deck) and `/out` (results). Ports: `4230` (dev), `8080` (serve, watch). Working directory: `/slides`.

### User ids

The container runs as `node` (uid 1000, gid 1000), never as root. Files written to `/out` belong to the user the
container runs as, so on Linux pass `--user "$(id -u):$(id -g)"` (or `SLIDES_UID`/`SLIDES_GID` in compose) and make sure that user may write to
the mounted folders. Create `out` yourself first: if Docker creates it, it belongs to root and the build cannot write to it.
Docker Desktop on macOS and Windows maps ownership for you. With any other uid there is no home folder; the entrypoint uses a scratch one under `/tmp`.
slide.ng writes a `.slide-ng/` scratch folder into the deck folder (add it to `.gitignore`; slide.ng's template does). For `build`, `export` and `export-notes` a
read-only `/slides` works: the deck is copied to `/tmp` first.

### Chromium and the sandbox

slide.ng starts Chromium itself with `--no-sandbox` (set in its code, not here), because Chromium's own sandbox needs privileges a normal
container does not have. So no `--privileged`, `SYS_ADMIN` capability or custom seccomp profile is needed, and none is used. The container is
the sandbox: the image runs as a non-root user, and the compose file drops all capabilities and sets `no-new-privileges`. Practical notes:

- Give export enough shared memory: `--shm-size=1g`. Docker's default 64 MB makes Chromium crash on big slides.
- Export only decks you trust, as with any browser: the deck is a web page that Chromium opens.
- The image has Liberation fonts and Noto Color Emoji. Add fonts for other scripts with `EXTRA_FONTS`, or install the fonts your deck uses; a missing font silently falls back.
- Chromium comes from Debian, not from Playwright. slide.ng never downloads a browser; it uses `CHROME_PATH`.
- A read-only root file system (`--read-only --tmpfs /tmp:exec,mode=1777`) is used by the `serve` and `watch` services in the example; not tried with `export`.

## Publishing the image

The workflow in `.github/workflows/build.yml` lints, tests and builds the image and runs a smoke test. It never pushes. To publish
(after slide.ng is on npm, or with a tarball your workflow can pack), add this to the `image` job in place of the build step and give the workflow
`packages: write` permission:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ghcr.io/${{ github.repository }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: ${{ github.ref == 'refs/heads/main' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: SLIDE_NG_SOURCE=${{ env.SLIDE_NG_SOURCE }}
```

Tag images with the slide.ng version they contain. For Docker Hub use `registry: docker.io` and repository secrets for the credentials.

## Development

```sh
bash tests/entrypoint.test.sh      # no Docker needed; needs bash, node 22, curl
bash tests/commit-msg.test.sh      # the commit message hook
shellcheck -x entrypoint.sh tests/entrypoint.test.sh
hadolint Dockerfile
```

The test uses a fake `slide-ng` that records its arguments and creates the files the real one would, and runs the real `serve.mjs`.
It cannot catch a problem inside the image (a missing package, a wrong path); that needs a real build. See [CONTRIBUTING.md](CONTRIBUTING.md).
License: MIT ([LICENSE](LICENSE)).

## Related repositories

- [slide.ng](https://github.com/slide-ng/slide.ng): the presentation tool itself.
- [slide.ng-themes](https://github.com/slide-ng/slide.ng-themes): the official themes.
- [slide.ng-starter](https://github.com/slide-ng/slide.ng-starter): a starter deck to copy.
- [slide.ng-docs](https://github.com/slide-ng/slide.ng-docs): the documentation site.
- [slide.ng-docker](https://github.com/slide-ng/slide.ng-docker): this container image.
- [slide.ng-vscode](https://github.com/slide-ng/slide.ng-vscode): a Visual Studio Code extension.

These addresses are placeholders until the repositories are published.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Changes follow the [Code of Conduct](CODE_OF_CONDUCT.md); security reports go through [SECURITY.md](SECURITY.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

Repository address used in this text: https://github.com/slide-ng/slide.ng-docker (a placeholder until the owner decides).

## Maintainers

<!-- prettier-ignore-start -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/erkamyaman"><img src="https://avatars.githubusercontent.com/u/88717125?v=4&s=100" width="100px;" alt="Erkam Yaman"/><br /><sub><b>Erkam Yaman</b></sub></a><br /><sub>Lead maintainer</sub></td>
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
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/erkamyaman"><img src="https://avatars.githubusercontent.com/u/88717125?v=4?s=100" width="100px;" alt="Erkam Yaman"/><br /><sub><b>Erkam Yaman</b></sub></a><br /><a href="https://github.com/slide-ng/slide.ng-docker/commits?author=erkamyaman" title="Code">💻</a> <a href="https://github.com/slide-ng/slide.ng-docker/commits?author=erkamyaman" title="Documentation">📖</a> <a href="#infra-erkamyaman" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#maintenance-erkamyaman" title="Maintenance">🚧</a></td>
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
