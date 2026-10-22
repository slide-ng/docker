#!/usr/bin/env bash
# Tests for entrypoint.sh and serve.mjs without Docker: a fake `slide-ng` records how it was called and writes
# the files the real one would (a build folder with the marker file, an export file).
#   bash tests/entrypoint.test.sh
# Needs bash, node 22 and curl. It does not build or run the image.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENTRY="${HERE}/entrypoint.sh"
SERVER="${HERE}/serve.mjs"
T=$(mktemp -d)
chmod 755 "$T"
BG_PIDS=()
cleanup() {
  local pid
  for pid in "${BG_PIDS[@]+"${BG_PIDS[@]}"}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$T"
}
trap cleanup EXIT

pass=0 fail=0 skip=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [[ -z ${2:-} ]] || printf '     %s\n' "$2"; }
check() { # check <name> <command...>: passes when the command succeeds
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}
has() { grep -q -- "$2" "$1"; }          # has <file> <text>
lacks() { ! grep -q -- "$2" "$1"; }

# --- the fake slide-ng ------------------------------------------------------
mkdir -p "$T/bin"
cat > "$T/bin/slide-ng" <<'FAKE'
#!/usr/bin/env bash
# Records "<cwd> | <args>" and acts like the real command in the way the entrypoint depends on.
echo "$(pwd) | $*" >> "$FAKE_LOG"
cmd=$1; shift
case $cmd in
  build)
    [[ ${FAKE_FAIL:-0} != 1 && ! -e "$FAKE_LOG.fail" ]] || { echo "fake build failed" >&2; exit 1; }
    out='' prev='' decks=()
    for a in "$@"; do [[ $prev == --out ]] && out=$a; [[ $a == *.md ]] && decks+=("$a"); prev=$a; done
    [[ ! -e $out ]] || { echo "fake: $out already exists" >&2; exit 1; }
    mkdir -p "$out"
    touch "$out/.slide-ng-build"
    if ((${#decks[@]} > 1)); then   # several decks: one folder each, named after the file
      for d in "${decks[@]}"; do n=$(basename "$d" .md); mkdir -p "$out/$n/assets"; cat "$d" > "$out/$n/index.html"; touch "$out/$n/assets/a.js"; done
    else
      mkdir -p "$out/assets"
      cat "${decks[0]}" > "$out/index.html"
      touch "$out/assets/a.js"
    fi
    ;;
  export | export-notes) echo pdf > "$(pwd)/talk.pdf" ;;
esac
FAKE
chmod +x "$T/bin/slide-ng"

# fresh_env: new deck, out and work folders for one test; sets the variables the entrypoint reads.
fresh_env() {
  rm -rf "${T:?}/case"
  mkdir -p "$T/case/slides" "$T/case/out" "$T/case/work"
  printf '# first\n' > "$T/case/slides/slides.md"
  : > "$T/case/log"
  export SLIDE_NG_BIN="$T/bin/slide-ng" SLIDES_DIR="$T/case/slides" OUT_DIR="$T/case/out" WORK_DIR="$T/case/work"
  export SERVER_JS="$SERVER" FAKE_LOG="$T/case/log" HOME="$T/case/home"
  mkdir -p "$HOME"
  unset SLIDES_PASSWORD SLIDES_PASSWORD_FILE SLIDES_NO_PASSWORD SLIDES_FILE PORT FAKE_FAIL
  export WATCH_INTERVAL=1
}
run() { bash "$ENTRY" "$@" >"$T/case/stdout" 2>"$T/case/stderr"; } # run <args>; output in case/stdout and case/stderr
free_port() { node -e 'const s=require("net").createServer().listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})'; }
wait_for() { # wait_for <url> [text]: waits up to 20 s until the address answers (with the text)
  local i
  for ((i = 0; i < 80; i++)); do
    if body=$(curl -fs "$1" 2>/dev/null) && [[ -z ${2:-} || $body == *"$2"* ]]; then return 0; fi
    sleep 0.25
  done
  return 1
}

# --- help and the command word ----------------------------------------------
fresh_env
run help
check "help lists every mode" bash -c "for m in dev build export serve watch; do grep -q \"^  \$m \" '$T/case/stdout' || exit 1; done"

run node -p 6*7
check "unknown first word runs as a command" has "$T/case/stdout" 42

run format
check "format goes to slide-ng" has "$T/case/log" "| format"

run skills install
check "skills goes to slide-ng" has "$T/case/log" "| skills install"

# --- missing deck -----------------------------------------------------------
fresh_env
rm "$SLIDES_DIR/slides.md"
for m in dev build export serve watch; do
  if run "$m"; then bad "$m without a deck fails"; else check "$m without a deck fails with a hint" has "$T/case/stderr" "not found"; fi
done
check "log lines use the [docker] prefix" has "$T/case/stderr" "^\\[docker\\] "
check "log lines drop the old repository name" lacks "$T/case/stderr" "slide.ng-docker"

# --- dev --------------------------------------------------------------------
fresh_env
run dev
check "dev: listens on 0.0.0.0" has "$T/case/log" "--bind 0.0.0.0"
check "dev: default port 4230" has "$T/case/log" "--port 4230"
check "dev: runs in the deck path" has "$T/case/log" "dev $SLIDES_DIR/slides.md"
check "dev: makes a password when none is given" has "$T/case/log" "--remote=[A-Za-z0-9]\{24\}"
check "dev: tells the generated password" has "$T/case/stderr" "made a random one"

fresh_env
SLIDES_PASSWORD='correct horse battery' run dev
check "dev: SLIDES_PASSWORD is used" has "$T/case/log" "--remote=correct horse battery"
check "dev: a given password is not printed by the entrypoint" lacks "$T/case/stderr" "correct horse"

fresh_env
printf 'from-a-file-123\nsecond line\n' > "$T/case/secret"
SLIDES_PASSWORD_FILE="$T/case/secret" run dev
check "dev: SLIDES_PASSWORD_FILE uses the first line" has "$T/case/log" "--remote=from-a-file-123$"

fresh_env
SLIDES_PASSWORD=abc run dev
check "dev: short password is a warning" has "$T/case/stderr" "shorter than 8"

fresh_env
SLIDES_NO_PASSWORD=1 run dev
check "dev: SLIDES_NO_PASSWORD gives plain --remote" has "$T/case/log" "--bind 0.0.0.0 --remote$"
check "dev: no password is warned about" has "$T/case/stderr" "warning"

fresh_env
run dev --remote=mine-mine-mine --port 9000
check "dev: own --remote wins, none is made" lacks "$T/case/stderr" "random"
check "dev: own flags come after ours" has "$T/case/log" "--remote=mine-mine-mine --port 9000"
check "dev: our --remote is not added twice" bash -c "[[ \$(grep -o -- '--remote' '$T/case/log' | wc -l) == 1 ]]"

fresh_env
PORT=5000 run dev
check "dev: PORT" has "$T/case/log" "--port 5000"

fresh_env
run --port 4300
check "no word and a flag mean dev" has "$T/case/log" "dev $SLIDES_DIR/slides.md"

fresh_env
cp "$SLIDES_DIR/slides.md" "$SLIDES_DIR/other.md"
run other.md
check "a .md name selects the deck" has "$T/case/log" "dev $SLIDES_DIR/other.md"

fresh_env
HOME=/nonexistent-home run dev
check "dev: falls back to a writable HOME" test -d "$T/case/work/home"

# --- build ------------------------------------------------------------------
fresh_env
run build --base /talk/ --download
check "build: output reaches /out" test -f "$OUT_DIR/index.html"
check "build: marker file is copied" test -f "$OUT_DIR/.slide-ng-build"
check "build: subfolders are copied" test -f "$OUT_DIR/assets/a.js"
check "build: flags are passed through" has "$T/case/log" "build slides.md --base /talk/ --download --out $WORK_DIR/dist"
check "build: runs in the deck folder" has "$T/case/log" "^$SLIDES_DIR |"
check "build: scratch build is removed" test ! -e "$WORK_DIR/dist"

echo "old" > "$OUT_DIR/old.txt"
printf '# second\n' > "$SLIDES_DIR/slides.md"
run build
check "build: a second build replaces the first (marker present)" bash -c "[[ ! -e '$OUT_DIR/old.txt' ]] && grep -q second '$OUT_DIR/index.html'"

fresh_env
echo "precious" > "$OUT_DIR/notes.txt"
if run build; then bad "build: refuses a /out with foreign files"; else
  check "build: refuses a /out with foreign files" bash -c "grep -q 'no .slide-ng-build' '$T/case/stderr' && [[ \$(cat '$OUT_DIR/notes.txt') == precious ]]"
fi

fresh_env
for flag in "--out x" "-o x" "--out=x"; do
  # shellcheck disable=SC2086
  if run build $flag; then bad "build: refuses $flag"; else check "build: refuses $flag" has "$T/case/stderr" "not allowed"; fi
done

fresh_env
echo "keep" > "$OUT_DIR/keep.txt"
FAKE_FAIL=1 run build || true
check "build: a failed build leaves /out alone" bash -c "[[ \$(cat '$OUT_DIR/keep.txt') == keep ]]"

fresh_env
printf '# deck a\n' > "$SLIDES_DIR/a.md"
printf '# deck b\n' > "$SLIDES_DIR/b.md"
run build a.md b.md --base /x/ --router-mode hash
check "build: several decks are passed to one build" has "$T/case/log" "build a.md b.md --base /x/ --router-mode hash --out $WORK_DIR/dist"
check "build: several decks land in their folders in /out" bash -c "grep -q 'deck a' '$OUT_DIR/a/index.html' && grep -q 'deck b' '$OUT_DIR/b/index.html'"
check "build: several decks keep the marker file" test -f "$OUT_DIR/.slide-ng-build"
if run build a.md missing.md; then bad "build: a missing deck among several fails"; else check "build: a missing deck among several fails" has "$T/case/stderr" "missing.md not found"; fi

# --- export -----------------------------------------------------------------
fresh_env
run export --format pdf --with-clicks
check "export: file lands in /out" test -f "$OUT_DIR/talk.pdf"
check "export: flags are passed through" has "$T/case/log" "export $SLIDES_DIR/slides.md --format pdf --with-clicks"
check "export: runs in /out" has "$T/case/log" "^$OUT_DIR |"
run export-notes
check "export-notes goes to slide-ng" has "$T/case/log" "| export-notes "

fresh_env
run export --format md --output talk.md
check "export: a flag's .md value is not a deck" has "$T/case/log" "export $SLIDES_DIR/slides.md --format md --output talk.md$"

fresh_env
printf '# deck a\n' > "$SLIDES_DIR/a.md"
printf '# deck b\n' > "$SLIDES_DIR/b.md"
run export a.md b.md --format pdf
check "export: several decks are passed together" has "$T/case/log" "export $SLIDES_DIR/a.md $SLIDES_DIR/b.md --format pdf$"

# --- serve ------------------------------------------------------------------
fresh_env
port=$(free_port)
PORT=$port bash "$ENTRY" serve --base /talk/ >"$T/case/stdout" 2>"$T/case/stderr" &
BG_PIDS+=($!)
if wait_for "http://127.0.0.1:$port/talk/" "first"; then ok "serve: builds and serves at the base"; else bad "serve: builds and serves at the base" "$(cat "$T/case/stderr")"; fi
check "serve: unknown deck address gets index.html" bash -c "curl -fs http://127.0.0.1:$port/talk/3 | grep -q first"
check "serve: missing asset is 404" bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$port/talk/nope.js) == 404 ]]"
check "serve: no path traversal" bash -c "[[ \$(curl -s --path-as-is -o /dev/null -w '%{http_code}' http://127.0.0.1:$port/talk/../../etc/passwd) == 404 ]]"
check "serve: / redirects to the base" bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$port/) == 302 ]]"
check "serve: base was passed to the build" has "$T/case/log" "build slides.md --base /talk/ --out $WORK_DIR/site"
kill "${BG_PIDS[-1]}" 2>/dev/null || true

fresh_env
mkdir -p "$T/case/dist"
echo "prebuilt" > "$T/case/dist/index.html"
port=$(free_port)
PORT=$port bash "$ENTRY" serve --dist "$T/case/dist" >"$T/case/stdout" 2>"$T/case/stderr" &
BG_PIDS+=($!)
if wait_for "http://127.0.0.1:$port/" "prebuilt"; then ok "serve --dist: serves a folder without building"; else bad "serve --dist: serves a folder without building"; fi
check "serve --dist: slide-ng is not called" test ! -s "$T/case/log"
kill "${BG_PIDS[-1]}" 2>/dev/null || true

fresh_env
printf '# deck a\n' > "$SLIDES_DIR/a.md"
printf '# deck b\n' > "$SLIDES_DIR/b.md"
port=$(free_port)
PORT=$port bash "$ENTRY" serve a.md b.md --base /x/ >"$T/case/stdout" 2>"$T/case/stderr" &
BG_PIDS+=($!)
if wait_for "http://127.0.0.1:$port/x/a/" "deck a"; then ok "serve: several decks, each at <base><name>/"; else bad "serve: several decks, each at <base><name>/" "$(cat "$T/case/stderr")"; fi
check "serve: a slide address gets its own deck's index.html" bash -c "curl -fs http://127.0.0.1:$port/x/b/presenter/3 | grep -q 'deck b'"
check "serve: a deck folder without the last slash redirects" bash -c "[[ \$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' http://127.0.0.1:$port/x/a) == '301 http://127.0.0.1:$port/x/a/' ]]"
check "serve: the base lists the decks" bash -c "curl -fs http://127.0.0.1:$port/x/ | grep -q 'href=\"b/\"'"
check "serve: several decks were built together" has "$T/case/log" "build a.md b.md --base /x/ --out $WORK_DIR/site"
kill "${BG_PIDS[-1]}" 2>/dev/null || true

# --- watch ------------------------------------------------------------------
fresh_env
port=$(free_port)
PORT=$port bash "$ENTRY" watch >"$T/case/stdout" 2>"$T/case/stderr" &
watch_pid=$!
BG_PIDS+=("$watch_pid")
if wait_for "http://127.0.0.1:$port/" "first"; then ok "watch: first build is served"; else bad "watch: first build is served" "$(cat "$T/case/stderr")"; fi
printf '# changed\n' > "$SLIDES_DIR/slides.md"
if wait_for "http://127.0.0.1:$port/" "changed"; then ok "watch: a change is rebuilt and served"; else bad "watch: a change is rebuilt and served" "$(cat "$T/case/stderr")"; fi
check "watch: the old build is removed" bash -c "[[ \$(ls -d '$WORK_DIR'/site-* | wc -l) == 1 ]]"
touch "$FAKE_LOG.fail"   # a flag file, because the running watch cannot see a new variable
printf '# broken\n' > "$SLIDES_DIR/slides.md"
sleep 3.5
check "watch: a failed rebuild keeps the last good site" bash -c "curl -fs http://127.0.0.1:$port/ | grep -q changed"
check "watch: a failed rebuild is reported" has "$T/case/stderr" "failed; still serving"
kill -TERM "$watch_pid"
stopped=0
for ((i = 0; i < 20; i++)); do kill -0 "$watch_pid" 2>/dev/null || { stopped=1; break; }; sleep 0.25; done
if ((stopped)); then ok "watch: stops on SIGTERM"; else bad "watch: stops on SIGTERM"; fi
check "watch: the server stops with it" bash -c "! curl -fs -m 2 http://127.0.0.1:$port/"

# --- read-only deck (needs a user other than root) --------------------------
if [[ $(id -u) == 0 ]] && command -v setpriv >/dev/null; then
  fresh_env
  chmod 755 "$T/case" "$T/case/slides" "$T/case/log"; chmod 666 "$T/case/log"
  chmod 777 "$T/case/out" "$T/case/work"; chmod 755 "$T/bin" "$T/bin/slide-ng"
  if setpriv --reuid 65534 --regid 65534 --clear-groups env HOME="$T/case/work/home" bash "$ENTRY" build >"$T/case/stdout" 2>"$T/case/stderr"; then
    check "read-only deck: built from a copy" has "$T/case/log" "^$WORK_DIR/deck |"
    check "read-only deck: output is written" test -f "$OUT_DIR/index.html"
  else
    bad "read-only deck: built from a copy" "$(cat "$T/case/stderr")"
  fi
else
  skip=$((skip + 1)); echo "skip read-only deck test (needs root and setpriv to run as another user)"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
((fail == 0))
