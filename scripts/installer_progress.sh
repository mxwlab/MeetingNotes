#!/bin/zsh

mn_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  print -r -- "$value"
}

mn_progress() {
  [[ "${MEETINGNOTES_PROGRESS_JSON:-false}" == true ]] || return 0
  local event="$1" id="$2" percent="$3" title="$4" detail="${5:-}"
  printf '@@MEETINGNOTES@@{"event":"%s","id":"%s","percent":%d,"title":"%s","detail":"%s"}\n' \
    "$(mn_json_escape "$event")" "$(mn_json_escape "$id")" "$percent" \
    "$(mn_json_escape "$title")" "$(mn_json_escape "$detail")"
}
