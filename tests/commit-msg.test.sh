#!/usr/bin/env bash
# Tests for .githooks/commit-msg: it must warn about a bad message and always exit with 0.
#   bash tests/commit-msg.test.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="${HERE}/.githooks/commit-msg"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0 fail=0
# run <message>: writes the message to a file, runs the hook, prints its warnings, fails if the exit code is not 0
run() {
  printf '%b' "$1" > "$T/msg"
  sh "$HOOK" "$T/msg" 2>&1
}
good() { # good <name> <message>: no warning
  local out; out=$(run "$2") || { fail=$((fail + 1)); printf 'FAIL %s (exit code)\n' "$1"; return; }
  if [[ -z $out ]]; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"; else fail=$((fail + 1)); printf 'FAIL %s\n     %s\n' "$1" "$out"; fi
}
warns() { # warns <name> <message> <text in the warning>
  local out; out=$(run "$2") || { fail=$((fail + 1)); printf 'FAIL %s (exit code)\n' "$1"; return; }
  if grep -qF -- "$3" <<<"$out"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"; else fail=$((fail + 1)); printf 'FAIL %s\n     %s\n' "$1" "$out"; fi
}

good  'type, scope and summary' 'feat(entrypoint): add the watch mode\n'
good  'no scope, with a body' 'fix: keep the exit code\n\nIt was lost.\n'
good  'comment lines are ignored' 'docs: explain the modes\n# Please enter the message\n'
good  'merge messages pass' 'Merge branch "x"\n'
good  'empty message' '\n'
warns 'missing type' 'Add a thing\n' 'type(scope): summary'
warns 'unknown type' 'feature: add a thing\n' 'is not a type'
warns 'unknown scope' 'feat(banana): add a thing\n' 'is not a scope'
warns 'trailing period' 'fix: add a thing.\n' 'period'
warns 'capital letter' 'fix: Add a thing\n' 'lower case'
warns 'long first line' "fix: $(printf 'a%.0s' $(seq 1 80))\n" 'characters'
warns 'no blank line' 'fix: a thing\nbody right away\n' 'blank line'
warns 'trailer line' 'fix: a thing\n\nWhy.\n\nCo-authored-by: Someone <a@example.com>\n' 'trailer'

# A missing message file must not break the commit.
sh "$HOOK" "$T/does-not-exist" && { pass=$((pass + 1)); echo 'ok   missing file'; } || { fail=$((fail + 1)); echo 'FAIL missing file'; }

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
