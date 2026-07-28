#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

project="$tmp/project"
fixture="$tmp/fixture"
mkdir -p "$project/scripts" "$fixture/imageio_ffmpeg/binaries"
cp "$ROOT/scripts/fetch_ffmpeg.sh" "$project/scripts/"

cat > "$fixture/imageio_ffmpeg/binaries/ffmpeg-macos-aarch64-v7.1" <<'FFMPEG'
#!/bin/zsh
if [[ "${1:-}" == "-version" ]]; then
  echo "ffmpeg version 7.1 test"
  exit 0
fi
exit 2
FFMPEG
chmod +x "$fixture/imageio_ffmpeg/binaries/ffmpeg-macos-aarch64-v7.1"
(cd "$fixture" && zip -q -r "$tmp/ffmpeg.whl" imageio_ffmpeg)
sha="$(shasum -a 256 "$tmp/ffmpeg.whl" | awk '{print $1}')"

mock_bin="$tmp/mock-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/curl" <<'CURL'
#!/bin/zsh
set -eu
: > "${MEETINGNOTES_TEST_CURL_MARKER:?}"
out=""
while (( $# )); do
  if [[ "$1" == "-o" ]]; then
    out="$2"
    shift 2
  else
    shift
  fi
done
cp "${MEETINGNOTES_TEST_ARCHIVE:?}" "$out"
CURL
chmod +x "$mock_bin/curl"

run_fetch() {
  PATH="$mock_bin:/usr/bin:/bin" \
  MEETINGNOTES_FFMPEG_URL="https://example.test/ffmpeg.whl" \
  MEETINGNOTES_FFMPEG_SHA256="$sha" \
  MEETINGNOTES_SKIP_ARCH_CHECK=true \
  MEETINGNOTES_TEST_ARCHIVE="$tmp/ffmpeg.whl" \
  MEETINGNOTES_TEST_CURL_MARKER="$tmp/curl.called" \
    "$project/scripts/fetch_ffmpeg.sh"
}

run_fetch
[[ -x "$project/bin/ffmpeg" ]] || { echo "FAIL binary"; exit 1; }
"$project/bin/ffmpeg" -version | grep -q "7.1" || { echo "FAIL version"; exit 1; }

rm "$tmp/curl.called"
run_fetch
[[ ! -e "$tmp/curl.called" ]] || { echo "FAIL idempotency"; exit 1; }

# 新期待版本的下载校验失败时，旧的可执行文件必须原样保留。
if PATH="$mock_bin:/usr/bin:/bin" \
  MEETINGNOTES_FFMPEG_VERSION="8.0" \
  MEETINGNOTES_FFMPEG_URL="https://example.test/ffmpeg.whl" \
  MEETINGNOTES_FFMPEG_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
  MEETINGNOTES_SKIP_ARCH_CHECK=true \
  MEETINGNOTES_TEST_ARCHIVE="$tmp/ffmpeg.whl" \
  MEETINGNOTES_TEST_CURL_MARKER="$tmp/curl.called" \
    "$project/scripts/fetch_ffmpeg.sh" >"$tmp/bad.log" 2>&1; then
  echo "FAIL bad checksum accepted"
  exit 1
fi
"$project/bin/ffmpeg" -version | grep -q "7.1" || { echo "FAIL old binary damaged"; exit 1; }

echo "PASS"
