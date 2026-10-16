# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Use GitHub's private reporting: open the **Security** tab of this repository and choose
**Report a vulnerability** (https://github.com/slide-ng/slide.ng-docker/security/advisories/new).
Include the image tag or commit, the command you ran, and what you saw.

If you cannot use GitHub, email erkamyaman35@gmail.com with "Security" in the subject.

You can expect a first answer within a week. Fixes are released as a new commit on `main`
and noted in the advisory.

## Scope

In scope: the `Dockerfile`, `entrypoint.sh`, `serve.mjs` and the example workflow and compose file
in this repository (for example a path traversal in the static server, or a default that exposes
the dev server without the password rules described in the README).

Out of scope: problems in slide.ng itself (report them to the slide.ng repository), in Node.js,
Debian or Chromium (report them upstream; rebuild the image to pick up fixes).

## What the image does by default

- Runs as the unprivileged user `node` (uid 1000), never as root.
- `dev` mode listens on every address of the container, so it needs a password. The entrypoint
  uses `SLIDES_PASSWORD`, or makes a random one and prints it. Running without a password needs
  an explicit `SLIDES_NO_PASSWORD=1`.
- The example compose file publishes ports on `127.0.0.1` only.
- There is no HTTPS. Put a reverse proxy in front for anything beyond a network you trust.
