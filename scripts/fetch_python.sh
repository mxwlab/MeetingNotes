#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
RUNTIME_ROOT="$BASE/runtime"
PYTHON_HOME="$RUNTIME_ROOT/python"
PYTHON_BIN="$PYTHON_HOME/bin/python3"
VENV="$BASE/venv"
VENV_PYTHON="$VENV/bin/python"
REQUIREMENTS="$BASE/requirements.txt"

# 官方来源：https://github.com/astral-sh/python-build-standalone/releases/tag/20260718
PYTHON_VERSION="${MEETINGNOTES_PYTHON_VERSION:-3.10.20}"
PYTHON_BUILD="${MEETINGNOTES_PYTHON_BUILD:-20260718}"
PYTHON_ASSET="cpython-${PYTHON_VERSION}+${PYTHON_BUILD}-aarch64-apple-darwin-install_only.tar.gz"
PYTHON_URL="${MEETINGNOTES_PYTHON_URL:-https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_BUILD}/${PYTHON_ASSET}}"
PYTHON_SHA256="${MEETINGNOTES_PYTHON_SHA256:-5ce056c4294bc7155cdd98ea35ee764bffebb08854c4910eb433cc5f4e45e9a5}"

fail() {
  echo "独立 Python 置备失败：$1" >&2
  exit 1
}

python_matches() {
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  "$candidate" --version 2>&1 | grep -Eq "^Python ${PYTHON_VERSION}([. ]|$)"
}

mkdir -p "$RUNTIME_ROOT"

if python_matches "$PYTHON_BIN"; then
  echo "独立 Python ${PYTHON_VERSION} 已存在"
else
  download="$(mktemp "$RUNTIME_ROOT/.python-download.XXXXXX")"
  stage="$(mktemp -d "$RUNTIME_ROOT/.python-stage.XXXXXX")"
  cleanup_fetch_python() {
    rm -f "$download"
    rm -rf "$stage"
  }
  trap cleanup_fetch_python EXIT

  echo "正在下载独立 Python ${PYTHON_VERSION}…"
  curl --fail --location --retry 3 --continue-at - \
    "$PYTHON_URL" -o "$download" \
    || fail "下载失败，请检查网络后重新运行"

  actual_sha="$(shasum -a 256 "$download" | awk '{print $1}')"
  [[ "$actual_sha" == "$PYTHON_SHA256" ]] \
    || fail "下载文件校验不通过（期待 $PYTHON_SHA256，实际 $actual_sha）"

  tar -xzf "$download" -C "$stage" \
    || fail "下载包无法解压"
  python_matches "$stage/python/bin/python3" \
    || fail "下载包内未找到可用的 Python ${PYTHON_VERSION}"

  previous=""
  if [[ -e "$PYTHON_HOME" ]]; then
    previous="$RUNTIME_ROOT/.python-previous.$$"
    mv "$PYTHON_HOME" "$previous"
  fi
  if ! mv "$stage/python" "$PYTHON_HOME"; then
    [[ -n "$previous" && -e "$previous" ]] && mv "$previous" "$PYTHON_HOME"
    fail "无法把 Python 安装到 $PYTHON_HOME"
  fi
  [[ -n "$previous" && -e "$previous" ]] && rm -rf "$previous"
  echo "独立 Python ${PYTHON_VERSION} 安装完成"
fi

[[ -f "$REQUIREMENTS" ]] || fail "缺少 requirements.txt"
requirements_sha="$(shasum -a 256 "$REQUIREMENTS" | awk '{print $1}')"
requirements_marker="$VENV/.meetingnotes-requirements.sha256"

if python_matches "$VENV_PYTHON" \
  && [[ -f "$requirements_marker" ]] \
  && [[ "$(<"$requirements_marker")" == "$requirements_sha" ]]; then
  echo "Python 依赖已安装，跳过"
  exit 0
fi

echo "正在创建 MeetingNotes Python 环境…"
if [[ ! -x "$VENV_PYTHON" ]]; then
  rm -rf "$VENV"
  "$PYTHON_BIN" -m venv "$VENV" \
    || fail "创建 Python 环境失败"
fi

echo "正在安装 Python 依赖…"
"$VENV_PYTHON" -m pip install --disable-pip-version-check -r "$REQUIREMENTS" \
  || fail "依赖安装失败，请检查网络后重新运行"
printf '%s\n' "$requirements_sha" > "$requirements_marker"

python_matches "$VENV_PYTHON" \
  || fail "Python 环境安装后验证失败"
echo "Python 运行环境准备完成"
