set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 提取 watch_inbox.sh 里被标记的配置解析块，保证测试校验的是真正出货的代码，
# 而不是测试里重抄的一份副本。
block="$(awk '/# >>> config-load/{f=1;next}/# <<< config-load/{f=0}f' "$DIR/watch_inbox.sh")"
[ -n "$block" ] || { echo "FAIL: 未能从 watch_inbox.sh 提取 config-load 块（标记缺失？）"; exit 1; }

# 情形A：存在 config.local.sh —— 应优先使用它
run_branch_a() {
  local tmp; tmp="$(mktemp -d)"
  local BASE="$tmp"
  local HOME="$tmp"
  printf 'export DEEPSEEK_API_KEY=fromconfig\n' > "$tmp/config.local.sh"
  local DEEPSEEK_API_KEY=""
  eval "$block"
  echo "$DEEPSEEK_API_KEY"
}
outA="$(run_branch_a)"
[ "$outA" = "fromconfig" ] || { echo "FAIL A: $outA"; exit 1; }

# 情形B：无 config.local.sh —— 回退读 ~/.zshrc
run_branch_b() {
  local tmp; tmp="$(mktemp -d)"
  local BASE="$tmp"
  local HOME="$tmp"
  printf 'export DEEPSEEK_API_KEY=fromzshrc\n' > "$tmp/.zshrc"
  local DEEPSEEK_API_KEY=""
  eval "$block"
  echo "$DEEPSEEK_API_KEY"
}
outB="$(run_branch_b)"
[ "$outB" = "fromzshrc" ] || { echo "FAIL B: $outB"; exit 1; }

echo "PASS"
