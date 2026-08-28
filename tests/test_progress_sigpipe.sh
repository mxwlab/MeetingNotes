#!/bin/zsh
# P1 回归：安装器窗口断开 stdout 读端后，安装绝不能被“报告进度失败”静默中止。
# 真实事故：bootstrap（set -eu）在模型步后写 stdout 收到 SIGPIPE（exit 141）静默退出，
# 后续步骤（后台服务/菜单栏/AirDrop）全没跑，GUI 停在 ~86%。
# 注意：不仅 mn_progress，连 step() 里的裸 echo 到断裂管道，在 set -e 下也会中止安装，
# 所以真正的防护是把 stdout 接到“只读不断”的转发器。这里复刻该机制并验证两类写都能存活。
set -eu

ROOT="${0:A:h:h}"

harness="$(mktemp)"
trap 'rm -f "$harness" "$harness.out"' EXIT
cat > "$harness" <<EOF
#!/bin/zsh
set -eu
trap '' PIPE
exec > >(trap '' PIPE; while IFS= read -r __l; do print -r -- "\$__l" 2>/dev/null || true; done)
source "$ROOT/scripts/installer_progress.sh"
export MEETINGNOTES_PROGRESS_JSON=true
i=0
while (( i < 2000 )); do
  echo "[\$i/8] 人类可读步骤行"                          # step() 风格的裸 echo
  mn_progress progress model "\$i" "正在下载" "已下载 \$i MB"  # 进度事件
  i=\$((i + 1))
done
print -r -- STEP6_REACHED > "$harness.out"
EOF
chmod +x "$harness"
: > "$harness.out"

# 读端只取头部就关闭，之后 bootstrap 侧持续写 -> 管道破裂
zsh "$harness" 2>/dev/null | head -c 100 >/dev/null || true
sleep 0.3

grep -Fq STEP6_REACHED "$harness.out" \
  || { echo "FAIL 管道断裂后未能继续执行后续步骤（echo/进度写把安装中止了）"; exit 1; }

# 静态断言：bootstrap 必须忽略 SIGPIPE，并在 GUI 模式装上不断裂的 stdout 转发器；
# 且 mn_progress 的 printf 不得让写失败向上传播。
grep -Eq "trap +'' +PIPE" "$ROOT/scripts/bootstrap_mac.sh" \
  || { echo "FAIL bootstrap_mac.sh 未忽略 SIGPIPE（缺 trap '' PIPE）"; exit 1; }
grep -Fq 'exec > >(' "$ROOT/scripts/bootstrap_mac.sh" \
  || { echo "FAIL bootstrap_mac.sh 未安装不断裂的 stdout 转发器"; exit 1; }
grep -Fq '|| true' "$ROOT/scripts/installer_progress.sh" \
  || { echo "FAIL mn_progress 的 printf 未用 || true 兜底写失败"; exit 1; }

echo PASS
