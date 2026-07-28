set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; cp "$DIR/watch_inbox.sh" "$tmp/"; mkdir -p "$tmp/inbox" "$tmp/logs"
# 情形A：存在 config.local.sh
printf 'export DEEPSEEK_API_KEY=fromconfig\n' > "$tmp/config.local.sh"
out=$(cd "$tmp" && zsh -c 'source ./config.local.sh; echo $DEEPSEEK_API_KEY')
[ "$out" = "fromconfig" ] || { echo "FAIL A: $out"; exit 1; }
echo "PASS"
