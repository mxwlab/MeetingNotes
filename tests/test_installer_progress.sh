#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
source "$ROOT/scripts/installer_progress.sh"

silent="$(MEETINGNOTES_PROGRESS_JSON=false mn_progress step_start python 10 '准备 Python' '预计 1–3 分钟')"
[[ -z "$silent" ]] || { echo "FAIL default output must stay silent"; exit 1; }

line="$(MEETINGNOTES_PROGRESS_JSON=true mn_progress step_start python 10 '准备 Python' '预计 1–3 分钟')"
python3 - "$line" <<'PY'
import json, sys
prefix = "@@MEETINGNOTES@@"
assert sys.argv[1].startswith(prefix)
event = json.loads(sys.argv[1][len(prefix):])
assert event == {
    "event": "step_start", "id": "python", "percent": 10,
    "title": "准备 Python", "detail": "预计 1–3 分钟",
}
PY

escaped="$(MEETINGNOTES_PROGRESS_JSON=true mn_progress error model 45 '下载失败' $'网络“中断”\n请重试')"
python3 - "$escaped" <<'PY'
import json, sys
event = json.loads(sys.argv[1].split("@@MEETINGNOTES@@", 1)[1])
assert event["detail"] == '网络“中断”\n请重试'
PY

grep -Fq 'du -sk "$model_dir"' "$ROOT/scripts/bootstrap_mac.sh" \
  || { echo "FAIL model progress is not driven by downloaded bytes"; exit 1; }
grep -Fq '预计还需约 ${remaining} 分钟' "$ROOT/scripts/bootstrap_mac.sh" \
  || { echo "FAIL model progress lacks remaining-time estimate"; exit 1; }

echo PASS
