#!/bin/zsh

BASE="${0:A:h}"
xattr -dr com.apple.quarantine "$BASE" 2>/dev/null || true

"$BASE/scripts/bootstrap_mac.sh"
rc=$?   # 注意：zsh 里 status 是只读内置变量($? 的别名)，不能赋值，故用 rc
if (( rc == 0 )); then
  echo
  echo "可以关闭这个窗口了。"
  exit 0
fi

echo
echo "安装暂未完成。修复提示的问题后，再双击这个文件即可继续。"
if [[ -t 0 ]]; then
  echo "按任意键关闭窗口…"
  read -k 1
fi
exit "$rc"
