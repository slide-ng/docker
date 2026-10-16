# slide.ng in a container: serve a deck, build it to a static site, or export it to PDF, PNG or PPTX.
# Usage and every variable are in the README. Build:
#   npm pack /path/to/slide.ng --pack-destination packages
#   docker build --build-arg SLIDE_NG_SOURCE=packages/slide-ng-core-0.1.0.tgz -t slide-ng .

# Node 22. slide.ng needs >= 22.22.3 (its "engines" field).
ARG NODE_VERSION=22.23.3
FROM node:${NODE_VERSION}-bookworm-slim

# --- 1. System packages: Chromium (for export, --download and the Open Graph picture), fonts, and tini
#        (a small init program, so signals reach our scripts and no zombie processes are left).
#        Add more fonts at build time, for example: --build-arg EXTRA_FONTS="fonts-noto-cjk"
ARG EXTRA_FONTS=""
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        chromium \
        fonts-liberation \
        fonts-noto-color-emoji \
        tini \
        ${EXTRA_FONTS} \
    && rm -rf /var/lib/apt/lists/*

# --- 2. slide.ng itself. A global install keeps its dependencies inside the package folder, which is
#        where slide.ng looks for them. SLIDE_NG_SOURCE is one of:
#          - a file inside this build context, such as packages/slide-ng-core-0.1.0.tgz (made with `npm pack`)
#          - anything npm understands: a package name or name@version
#        slide.ng is not on npm yet, so the default (slide-ng) only works once it is published.
ARG SLIDE_NG_SOURCE=slide-ng
COPY packages/ /tmp/context/packages/
# slide.ng never downloads a browser (it uses CHROME_PATH), this only makes that certain for its dependencies.
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
# The version is part of SLIDE_NG_SOURCE, chosen by whoever builds, so the DL3016 rule does not apply.
# hadolint ignore=DL3016
RUN if [ -f "/tmp/context/${SLIDE_NG_SOURCE}" ]; then spec="/tmp/context/${SLIDE_NG_SOURCE}"; else spec="${SLIDE_NG_SOURCE}"; fi \
    && npm install --global --no-audit --no-fund "${spec}" \
    && npm cache clean --force \
    && rm -rf /tmp/context \
    && slide-ng --help > /dev/null

# --- 3. Our scripts.
COPY --chmod=0755 entrypoint.sh /usr/local/bin/slide-ng-entrypoint
COPY serve.mjs /usr/local/lib/slide-ng-docker/serve.mjs

# --- 4. Folders and the unprivileged user. The base image already has user `node` (uid 1000, gid 1000).
#        /slides is the deck (mount it), /out is where results go (mount it).
RUN mkdir -p /slides /out \
    && chown node:node /slides /out

# --- 5. Run settings.
ENV CHROME_PATH=/usr/bin/chromium \
    SLIDE_NG_NO_SANDBOX=1 \
    NG_CLI_ANALYTICS=false
# uid 1000 is the base image's `node` user.
USER 1000:1000
WORKDIR /slides
# 4230: dev server (mode dev). 8080: static server (modes serve and watch).
EXPOSE 4230 8080
ENTRYPOINT ["tini", "--", "slide-ng-entrypoint"]
CMD ["dev"]
