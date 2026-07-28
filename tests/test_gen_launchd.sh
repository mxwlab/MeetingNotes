#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$ROOT/scripts/gen_launchd.sh"
tmp_plist="$(mktemp)"
trap 'rm -f "$tmp_plist"' EXIT

out="$("$GEN" /tmp/foo)"
expected_hash="$(printf '%s' /tmp/foo | shasum | cut -c1-8)"

print -r -- "$out" | grep -q "<string>com.meetingnotes.$expected_hash</string>" \
  || { echo "FAIL label"; exit 1; }
print -r -- "$out" | grep -q "<string>/tmp/foo/watch_inbox.sh</string>" \
  || { echo "FAIL program path"; exit 1; }
print -r -- "$out" | grep -q "<string>/tmp/foo/inbox</string>" \
  || { echo "FAIL watch path"; exit 1; }
print -r -- "$out" | grep -q "<string>/tmp/foo/logs/launchd.out.log</string>" \
  || { echo "FAIL stdout path"; exit 1; }
print -r -- "$out" | grep -q "<string>/tmp/foo/logs/launchd.err.log</string>" \
  || { echo "FAIL stderr path"; exit 1; }

print -r -- "$out" > "$tmp_plist"
plutil -lint "$tmp_plist" >/dev/null || { echo "FAIL invalid plist"; exit 1; }

special_out="$("$GEN" 'relative & special')"
print -r -- "$special_out" | grep -q "$ROOT/relative &amp; special/inbox" \
  || { echo "FAIL XML escaping or absolute path"; exit 1; }
print -r -- "$special_out" | grep -q '__PROJECT__\|__LABEL__' \
  && { echo "FAIL unresolved placeholder"; exit 1; }
print -r -- "$special_out" > "$tmp_plist"
plutil -lint "$tmp_plist" >/dev/null || { echo "FAIL invalid special-path plist"; exit 1; }

echo "PASS"
