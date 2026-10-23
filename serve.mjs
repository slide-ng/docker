#!/usr/bin/env node
// A tiny static file server for a built deck. Node only, no packages.
//   node serve.mjs <folder> [--port 8080] [--host 0.0.0.0] [--base /talk/]
//
// What it does, and nothing more:
//   - serves files from <folder> (the folder may be a symlink; it is looked at again on every request,
//     so the watch mode can swap in a new build)
//   - an address without a file extension (/3, /presenter/1) gets index.html, because the deck is a single-page app
//   - the deck lives under --base (the same value the deck was built with); "/" redirects there
//   - several decks built together (`slide-ng build a.md b.md`) live in <base>a/ and <base>b/: an address gets the
//     index.html of the deck it is in, and <base> itself lists the decks
//   - supports HEAD and Range requests (video seeking), refuses dot files and anything outside the folder
// It does not compress and has no HTTPS. Put a reverse proxy in front for that.
import { createReadStream, readdirSync, realpathSync, statSync } from 'node:fs';
import http from 'node:http';
import { extname, join, resolve, sep } from 'node:path';
import { parseArgs } from 'node:util';

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.webmanifest': 'application/manifest+json',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif',
  '.webp': 'image/webp', '.avif': 'image/avif', '.ico': 'image/x-icon', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.wasm': 'application/wasm', '.mp4': 'video/mp4', '.webm': 'video/webm',
  '.mp3': 'audio/mpeg', '.ogg': 'audio/ogg', '.pdf': 'application/pdf', '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.map': 'application/json', '.txt': 'text/plain; charset=utf-8', '.md': 'text/markdown; charset=utf-8',
};

/** `/talk`, `talk/` and `/talk/` all become `/talk/`. Only plain path pieces are accepted. */
export function normalizeBase(base = '/') {
  const path = `/${base}/`.replace(/\/+/g, '/');
  if (!/^\/([\w.~-]+\/)*$/.test(path) || path.includes('/../') || path.includes('/./')) {
    throw new Error(`--base must be a path such as /talk/, got "${base}"`);
  }
  return path;
}

/** The real file a request path names inside `root`, or null (not a file, a dot file, or outside the folder). */
export function resolveFile(root, base, pathname) {
  let path;
  try { path = decodeURIComponent(pathname); } catch { return null; }
  if (path.includes('\0') || !path.startsWith(base)) return null;
  const relative = path.slice(base.length);
  if (relative.split('/').some((part) => part.startsWith('.'))) return null; // .slide-ng-build, .git, ..
  try {
    const realRoot = realpathSync(root);
    const file = realpathSync(join(realRoot, relative));
    if (file !== realRoot && !file.startsWith(realRoot + sep)) return null; // a symlink led out
    return statSync(file).isFile() ? file : null;
  } catch { return null; }
}

// File names with a hash (main-ABCD1234.js, and inline-0123456789ab.js for the scripts slide.ng moves out of
// index.html) never change; the entry points do.
const HASHED = /(-[A-Za-z0-9_-]{8}\.(js|css|woff2?|png|jpg|svg)|\/inline-[0-9a-f]{12}\.js)$/;
const cacheControl = (file) => (HASHED.test(file) ? 'public, max-age=31536000, immutable' : 'no-cache');

/** The index.html of the deck an address belongs to: the nearest one at or above the address, not above `base`. */
export function deckIndex(root, base, pathname) {
  let dir = pathname.slice(0, pathname.lastIndexOf('/') + 1);
  while (dir.startsWith(base)) {
    const file = resolveFile(root, base, `${dir}index.html`);
    if (file || dir === base) return file;
    dir = dir.slice(0, dir.lastIndexOf('/', dir.length - 2) + 1);
  }
  return null;
}

/** The folders right under `root` that hold a deck (an index.html), for a build of several decks. */
export function deckFolders(root) {
  try {
    return readdirSync(root, { withFileTypes: true })
      .filter((entry) => !entry.name.startsWith('.') && resolveFile(root, '/', `/${entry.name}/index.html`))
      .map((entry) => entry.name)
      .sort();
  } catch { return []; }
}

const escapeHtml = (text) => text.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** `bytes=a-b` for a file of `size` bytes: [start, end], or null when it is not a usable single range. */
export function parseRange(header, size) {
  const m = /^bytes=(\d*)-(\d*)$/.exec(header ?? '');
  if (!m || (m[1] === '' && m[2] === '')) return null;
  let start = m[1] === '' ? size - Number(m[2]) : Number(m[1]);
  let end = m[1] === '' || m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
  start = Math.max(start, 0);
  return start <= end && start < size ? [start, end] : null;
}

export function createDeckServer({ root, base = '/' }) {
  base = normalizeBase(base);
  return http.createServer((req, res) => {
    const send = (status, text, headers = {}) => { res.writeHead(status, { 'content-type': 'text/plain; charset=utf-8', ...headers }); res.end(req.method === 'HEAD' ? undefined : text); };
    if (req.method !== 'GET' && req.method !== 'HEAD') return send(405, 'method not allowed', { allow: 'GET, HEAD' });

    const pathname = new URL(req.url, 'http://x').pathname;
    if (base !== '/' && pathname === base.slice(0, -1)) return send(301, '', { location: base });
    if (base !== '/' && !pathname.startsWith(base)) return pathname === '/' ? send(302, '', { location: base }) : send(404, 'not found');

    let file = resolveFile(root, base, pathname);
    if (!file && !extname(pathname)) {
      // A deck's folder written without the last slash (/talk/a): go to /talk/a/, where its files are found.
      if (!pathname.endsWith('/') && !pathname.startsWith('//') && resolveFile(root, base, `${pathname}/index.html`)) return send(301, '', { location: `${pathname}/` });
      file = deckIndex(root, base, pathname);
      if (!file && pathname === base) {
        const decks = deckFolders(root);
        if (decks.length) {
          const list = decks.map((name) => `<li><a href="${escapeHtml(name)}/">${escapeHtml(name)}</a></li>`).join('');
          return send(200, `<!doctype html><meta charset="utf-8"><title>Decks</title><ul>${list}</ul>\n`, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-cache', 'x-content-type-options': 'nosniff' });
        }
      }
    }
    if (!file) return send(404, 'not found');

    const size = statSync(file).size;
    const headers = {
      'content-type': TYPES[extname(file).toLowerCase()] ?? 'application/octet-stream',
      'cache-control': cacheControl(file), 'accept-ranges': 'bytes', 'x-content-type-options': 'nosniff',
    };
    const range = parseRange(req.headers.range, size);
    if (req.headers.range && !range) return send(416, 'range not satisfiable', { 'content-range': `bytes */${size}` });
    if (range) res.writeHead(206, { ...headers, 'content-range': `bytes ${range[0]}-${range[1]}/${size}`, 'content-length': range[1] - range[0] + 1 });
    else res.writeHead(200, { ...headers, 'content-length': size });
    if (req.method === 'HEAD') return res.end();
    createReadStream(file, range ? { start: range[0], end: range[1] } : {}).on('error', () => res.destroy()).pipe(res);
  });
}

// Run as a program (not when a test imports it).
if (process.argv[1] && resolve(process.argv[1]) === resolve(new URL(import.meta.url).pathname)) {
  try {
    const { values, positionals } = parseArgs({
      allowPositionals: true,
      options: { port: { type: 'string', default: '8080' }, host: { type: 'string', default: '0.0.0.0' }, base: { type: 'string', default: '/' } },
    });
    if (positionals.length !== 1) throw new Error('usage: serve.mjs <folder> [--port 8080] [--host 0.0.0.0] [--base /talk/]');
    const port = Number(values.port);
    if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error(`--port must be a number from 0 to 65535, got "${values.port}"`);
    const server = createDeckServer({ root: positionals[0], base: values.base });
    server.listen(port, values.host, () => {
      console.log(`[serve] ${resolve(positionals[0])} at http://${values.host}:${server.address().port}${normalizeBase(values.base)}`);
    });
    for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { server.closeAllConnections(); server.close(() => process.exit(0)); });
  } catch (error) {
    console.error(`[serve] ${error.message}`);
    process.exit(2);
  }
}
