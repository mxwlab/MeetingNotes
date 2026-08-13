#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
grep -Fq 'open "$INSTALLER"' "$ROOT/开始使用.command" \
  || { echo "FAIL launcher does not prefer native installer"; exit 1; }
! grep -Fq 'open -W' "$ROOT/开始使用.command" \
  || { echo "FAIL launcher keeps Terminal waiting behind installer"; exit 1; }
grep -Fq '图形安装助手暂时无法启动' "$ROOT/开始使用.command" \
  || { echo "FAIL launcher lacks terminal fallback"; exit 1; }
echo PASS
