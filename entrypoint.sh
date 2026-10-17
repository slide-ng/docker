#!/usr/bin/env bash
# Entry point of the slide.ng image.
#
#   docker run IMAGE [mode] [flags...]
#
# Modes (the flags after the mode are passed to slide-ng):
#   dev      serve the deck with live reload (needs a password, see below)       default
#   build    static site into /out
#   export   pdf, png, pptx or md file into /out
#   export-notes   speaker notes as a pdf into /out
#   serve    build the deck, then serve the static site on port 8080
#   watch    like serve, and rebuild when a file in /slides changes
#   help     print this text
# Any other first word is run as a command (`slide-ng format`, `node -v`, `bash`).
#
# Settings (environment variables):
#   SLIDES_FILE      deck file name inside /slides                   (slides.md)
#   SLIDES_PASSWORD  password for dev mode; SLIDES_PASSWORD_FILE reads it from a file (Docker secret)
#   SLIDES_NO_PASSWORD=1   dev mode without a password (slide.ng prints a warning)
#   PORT             dev: 4230, serve and watch: 8080
#   WATCH_INTERVAL   seconds between checks in watch mode            (2)
#
# Files: the deck is read from /slides, results go to /out. Both can be moved for tests:
# SLIDES_DIR, OUT_DIR, WORK_DIR (scratch space), SLIDE_NG_BIN (the slide-ng program), SERVER_JS.
set -euo pipefail

SLIDE_NG_BIN=${SLIDE_NG_BIN:-slide-ng}
SLIDES_DIR=${SLIDES_DIR:-/slides}
OUT_DIR=${OUT_DIR:-/out}
WORK_DIR=${WORK_DIR:-/tmp/slide-ng-work}
SERVER_JS=${SERVER_JS:-/usr/local/lib/slide-ng-docker/serve.mjs}
SLIDES_FILE=${SLIDES_FILE:-slides.md}
WATCH_INTERVAL=${WATCH_INTERVAL:-2}
MARKER=.slide-ng-build   # slide.ng only empties a folder that has this file (scripts/cli/safe-dir.mjs)

log() { printf '[docker] %s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- environment

# A container started with --user <any id> has no home folder. Chromium and Angular want a writable one.
ensure_home() {
  if [[ -z "${HOME:-}" || ! -w "${HOME}" ]]; then
    export HOME="${WORK_DIR}/home"
    mkdir -p "$HOME"
  fi
  export NG_CLI_ANALYTICS=false
}

need_deck() {
  [[ -f "${SLIDES_DIR}/${SLIDES_FILE}" ]] || die "${SLIDES_DIR}/${SLIDES_FILE} not found. Mount your deck folder: -v \"\$PWD:${SLIDES_DIR}\" (or set SLIDES_FILE)."
}

need_writable() { # need_writable <folder> <what it is for>
  [[ -d "$1" && -w "$1" ]] || die "$1 is missing or not writable by uid $(id -u). $2"
}

# Options we set ourselves cannot be given again.
refuse_flag() { # refuse_flag <mode> <message> <flag...> -- <args...>
  local mode=$1 message=$2; shift 2
  local flags=() arg flag
  while [[ $1 != -- ]]; do flags+=("$1"); shift; done
  shift
  for arg in "$@"; do
    for flag in "${flags[@]}"; do
      if [[ $arg == "$flag" || $arg == "$flag="* ]]; then die "${mode}: ${flag} is not allowed. ${message}"; fi
    done
  done
}

# ---------------------------------------------------------------- the deck

# Prints the folder slide.ng should work in. slide.ng writes a scratch folder (.slide-ng) next to the deck;
# when /slides is read-only (-v ...:ro) the deck is copied to a scratch place first.
stage_deck() {
  if [[ -w "$SLIDES_DIR" ]]; then
    printf '%s\n' "$SLIDES_DIR"
    return
  fi
  local copy="${WORK_DIR}/deck"
  rm -rf "$copy"
  mkdir -p "$copy"
  tar -C "$SLIDES_DIR" --exclude=./.slide-ng -cf - . | tar -C "$copy" -xf -
  printf '%s\n' "$copy"
}

# build_site <destination> [slide-ng build flags]: builds the deck into a folder that does not exist yet.
build_site() {
  local dest=$1; shift
  local deck
  deck=$(stage_deck)
  mkdir -p "$(dirname "$dest")"
  (cd "$deck" && "$SLIDE_NG_BIN" build "$SLIDES_FILE" "$@" --out "$dest")
}

# publish_site <built folder>: copies a build into /out. /out is usually a mount point, so it cannot be
# deleted and recreated the way slide.ng does it; its content is replaced instead, with the same safety rule:
# only a folder that is empty or came from an earlier build (it has the marker file) is emptied.
publish_site() {
  local from=$1
  need_writable "$OUT_DIR" "Mount a folder: -v \"\$PWD/out:${OUT_DIR}\" (create it first and give it to your user, or run with --user \"\$(id -u):\$(id -g)\")."
  case "$(realpath "$OUT_DIR")" in / | "$HOME") die "refusing to empty $OUT_DIR" ;; esac
  if [[ -n "$(ls -A "$OUT_DIR")" && ! -e "${OUT_DIR}/${MARKER}" ]]; then
    die "${OUT_DIR} has files that no slide.ng build wrote (no ${MARKER} file). Use an empty folder."
  fi
  find "$OUT_DIR" -mindepth 1 -delete
  # No -a: keeping owner and times of "." fails when /out belongs to another user and is only writable.
  cp -R "$from"/. "$OUT_DIR"/
}

# ---------------------------------------------------------------- modes

mode_dev() {
  need_deck
  need_writable "$SLIDES_DIR" "dev mode saves edits and drawings into the deck; mount it without :ro and as a user who may write to it."
  local args=("$@") remote_given=0 arg
  for arg in "${args[@]}"; do [[ $arg == --remote || $arg == --remote=* ]] && remote_given=1; done

  local remote=()
  if ((remote_given)); then
    log "using the --remote option you passed"
  else
    remote=(--remote)
    local password=${SLIDES_PASSWORD:-}
    if [[ -z $password && -n ${SLIDES_PASSWORD_FILE:-} ]]; then
      [[ -r $SLIDES_PASSWORD_FILE ]] || die "SLIDES_PASSWORD_FILE ${SLIDES_PASSWORD_FILE} cannot be read"
      password=$(head -n 1 "$SLIDES_PASSWORD_FILE")
    fi
    if [[ -n $password ]]; then
      [[ $password != *$'\n'* ]] || die "the password must be one line"
      ((${#password} >= 8)) || log "warning: the password is shorter than 8 characters"
      remote=("--remote=${password}")
    elif [[ ${SLIDES_NO_PASSWORD:-} == 1 ]]; then
      log "warning: SLIDES_NO_PASSWORD=1, anyone who can reach the port can open the deck and drive the presenter"
    else
      password=$(head -c 24 /dev/urandom | base64 | tr -d '/+=\n' | head -c 24)
      log "no SLIDES_PASSWORD given, made a random one: ${password}"
      remote=("--remote=${password}")
    fi
  fi

  ensure_home
  # Our defaults come first, so a flag you pass (for example --port) wins.
  # Inside a container the server must listen on every address, or the published port reaches nothing.
  exec "$SLIDE_NG_BIN" dev "${SLIDES_DIR}/${SLIDES_FILE}" --port "${PORT:-4230}" --bind 0.0.0.0 "${remote[@]}" "${args[@]}"
}

mode_build() {
  need_deck
  refuse_flag build "The output folder is ${OUT_DIR}; mount it with -v." --out -o -- "$@"
  ensure_home
  rm -rf "${WORK_DIR}/dist"
  build_site "${WORK_DIR}/dist" "$@"
  publish_site "${WORK_DIR}/dist"
  rm -rf "${WORK_DIR}/dist"
  log "static site written to ${OUT_DIR}"
}

mode_export() { # export and export-notes
  local command=$1; shift
  need_deck
  need_writable "$OUT_DIR" "Mount a folder: -v \"\$PWD/out:${OUT_DIR}\" and run with --user \"\$(id -u):\$(id -g)\"."
  ensure_home
  local deck
  deck=$(stage_deck)
  # slide.ng writes the file into the current folder (unless --output says otherwise), so work from /out.
  cd "$OUT_DIR"
  "$SLIDE_NG_BIN" "$command" "${deck}/${SLIDES_FILE}" "$@"
}

# The base path a build was made for, from its flags (needed by the server). `--base /talk/` or `--base=/talk/`.
base_from_flags() {
  local previous='' arg
  for arg in "$@"; do
    [[ $previous == --base ]] && { printf '%s\n' "$arg"; return; }
    [[ $arg == --base=* ]] && { printf '%s\n' "${arg#--base=}"; return; }
    previous=$arg
  done
  printf '/\n'
}

# swap_current <built folder>: makes `current` point to a build. The swap is atomic; the server follows the link.
swap_current() {
  local target=$1
  ln -sfn "$target" "${WORK_DIR}/current.tmp"
  mv -T "${WORK_DIR}/current.tmp" "${WORK_DIR}/current"
}

start_server() { # start_server <folder> <base>; sets SERVER_PID
  node "$SERVER_JS" "$1" --port "${PORT:-8080}" --host 0.0.0.0 --base "$2" &
  SERVER_PID=$!
}

mode_serve() {
  local dist='' args=() base
  while (($#)); do
    case $1 in
      --dist) [[ $# -ge 2 ]] || die "serve: --dist needs a folder"; dist=$2; shift 2 ;;
      --dist=*) dist=${1#--dist=}; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  base=$(base_from_flags "${args[@]+"${args[@]}"}")
  if [[ -n $dist ]]; then
    [[ -f "${dist}/index.html" ]] || die "serve: ${dist}/index.html not found (is it a built deck?)"
    log "serving ${dist} (no build)"
    exec node "$SERVER_JS" "$dist" --port "${PORT:-8080}" --host 0.0.0.0 --base "$base"
  fi
  need_deck
  ensure_home
  mkdir -p "$WORK_DIR"
  rm -rf "${WORK_DIR}/site"
  build_site "${WORK_DIR}/site" "${args[@]+"${args[@]}"}"
  exec node "$SERVER_JS" "${WORK_DIR}/site" --port "${PORT:-8080}" --host 0.0.0.0 --base "$base"
}

# A short fingerprint of everything that can change a build. Scratch folders are skipped.
fingerprint() {
  find "$SLIDES_DIR" \( -name .slide-ng -o -name node_modules -o -name .git \) -prune -o -type f -printf '%p %T@ %s\n' | sort | cksum
}

mode_watch() {
  need_deck
  ensure_home
  mkdir -p "$WORK_DIR"
  local args=("$@") base n=0 seen now
  base=$(base_from_flags "${args[@]+"${args[@]}"}")

  rebuild() {
    n=$((n + 1))
    local next="${WORK_DIR}/site-${n}" old
    old=$(readlink "${WORK_DIR}/current" 2>/dev/null || true)
    if build_site "$next" "${args[@]+"${args[@]}"}"; then
      swap_current "$next"
      [[ -z $old ]] || rm -rf "$old"
      log "build ${n} is live"
    else
      rm -rf "$next"
      log "build ${n} failed; still serving ${old:-nothing}. Fix the deck, the next change builds again."
      [[ -n $old ]]
    fi
  }

  seen=$(fingerprint)
  rebuild || die "the first build failed"
  start_server "${WORK_DIR}/current" "$base"
  trap 'kill "$SERVER_PID" 2>/dev/null; exit 0' INT TERM

  while kill -0 "$SERVER_PID" 2>/dev/null; do
    sleep "$WATCH_INTERVAL" & wait $! || true
    now=$(fingerprint)
    if [[ $now != "$seen" ]]; then
      seen=$now
      log "change found, building"
      rebuild || true
    fi
  done
  die "the server stopped"
}

# ---------------------------------------------------------------- main

main() {
  # Like slide-ng itself: no word, a flag or a .md file means dev. A .md file name replaces SLIDES_FILE.
  if (($# > 0)) && [[ $1 == *.md ]]; then SLIDES_FILE=$1; shift; fi
  if (($# == 0)) || [[ $1 == -* ]]; then set -- dev "$@"; fi
  local mode=$1; shift
  case $mode in
    dev) mode_dev "$@" ;;
    build) mode_build "$@" ;;
    export | export-notes) mode_export "$mode" "$@" ;;
    serve) mode_serve "$@" ;;
    watch) mode_watch "$@" ;;
    help) usage ;;
    format | create | theme | mcp) ensure_home; exec "$SLIDE_NG_BIN" "$mode" "$@" ;;
    *) exec "$mode" "$@" ;;
  esac
}

# Not run when a test sources this file.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
