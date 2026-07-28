#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

project="$tmp/project"
fixture="$tmp/fixture"
mkdir -p "$project/scripts" "$fixture/python/bin"
cp "$ROOT/scripts/fetch_python.sh" "$project/scripts/"
printf 'fake dependency\n' > "$project/requirements.txt"

cat > "$fixture/python/bin/python3" <<'PY'
#!/bin/zsh
set -eu
if [[ "${1:-}" == "--version" ]]; then
  echo "Python 3.10.20"
elif [[ "${1:-}" == "-m" && "${2:-}" == "venv" ]]; then
  target="$3"
  mkdir -p "$target/bin"
  cat > "$target/bin/python" <<'VENV'
#!/bin/zsh
set -eu
if [[ "${1:-}" == "--version" ]]; then
  echo "Python 3.10.20"
elif [[ "${1:-}" == "-m" && "${2:-}" == "pip" ]]; then
  : > "${MEETINGNOTES_TEST_PIP_MARKER:?}"
else
  exit 2
fi
VENV
  chmod +x "$target/bin/python"
else
  exit 2
fi
PY
chmod +x "$fixture/python/bin/python3"
tar -czf "$tmp/python.tar.gz" -C "$fixture" python
sha="$(shasum -a 256 "$tmp/python.tar.gz" | awk '{print $1}')"

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
  MEETINGNOTES_PYTHON_URL="https://example.test/python.tar.gz" \
  MEETINGNOTES_PYTHON_SHA256="$sha" \
  MEETINGNOTES_TEST_ARCHIVE="$tmp/python.tar.gz" \
  MEETINGNOTES_TEST_CURL_MARKER="$tmp/curl.called" \
  MEETINGNOTES_TEST_PIP_MARKER="$tmp/pip.called" \
    "$project/scripts/fetch_python.sh"
}

run_fetch
[[ -x "$project/runtime/python/bin/python3" ]] || { echo "FAIL runtime"; exit 1; }
[[ -x "$project/venv/bin/python" ]] || { echo "FAIL venv"; exit 1; }
[[ -f "$tmp/curl.called" && -f "$tmp/pip.called" ]] || { echo "FAIL orchestration"; exit 1; }

# 可用的固定版本与已存在 venv 应完全幂等，不再下载或装依赖。
rm "$tmp/curl.called" "$tmp/pip.called"
run_fetch
[[ ! -e "$tmp/curl.called" && ! -e "$tmp/pip.called" ]] || { echo "FAIL idempotency"; exit 1; }

# 校验失败不得覆盖一个已存在且可用的 runtime。
rm -rf "$project/venv"
if PATH="$mock_bin:/usr/bin:/bin" \
  MEETINGNOTES_PYTHON_VERSION="3.11.0" \
  MEETINGNOTES_PYTHON_URL="https://example.test/python.tar.gz" \
  MEETINGNOTES_PYTHON_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
  MEETINGNOTES_TEST_ARCHIVE="$tmp/python.tar.gz" \
  MEETINGNOTES_TEST_CURL_MARKER="$tmp/curl.called" \
  MEETINGNOTES_TEST_PIP_MARKER="$tmp/pip.called" \
    "$project/scripts/fetch_python.sh" >"$tmp/bad.log" 2>&1; then
  echo "FAIL bad checksum accepted"
  exit 1
fi
"$project/runtime/python/bin/python3" --version | grep -q "3.10.20" \
  || { echo "FAIL existing runtime damaged"; exit 1; }

echo "PASS"
