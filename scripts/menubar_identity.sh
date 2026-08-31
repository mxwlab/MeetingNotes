#!/bin/zsh

# 菜单栏服务必须按安装路径隔离。否则同一用户会话中的正式实例、验收沙盒和旧版本
# 会争用同一个 LaunchAgent label / bundle identity，最终露出来的可能是一只永远空闲的猫。

mn_menubar_default_label() {
  local base="${1:A}"
  local path_hash
  path_hash="$(printf '%s' "$base" | shasum | cut -c1-8)"
  print -r -- "com.moxiuwen.meetingnotes.menubar.$path_hash"
}

mn_menubar_label() {
  local base="${1:A}"
  local marker="$base/.menubar_label"
  local label="${MEETINGNOTES_MENUBAR_LABEL:-}"

  if [[ -z "$label" && -f "$marker" ]]; then
    label="$(head -n 1 "$marker")"
  fi
  [[ -n "$label" ]] || label="$(mn_menubar_default_label "$base")"
  [[ "$label" =~ '^[A-Za-z0-9._-]+$' ]] || {
    print -u2 "菜单栏服务名包含无效字符：$label"
    return 2
  }
  print -r -- "$label"
}

mn_menubar_bundle_id() {
  local label="$1"
  # Apple bundle identifier 不使用下划线；LaunchAgent label 里的下划线安全替换为连字符。
  print -r -- "${label//_/-}"
}

mn_write_menubar_label() {
  local base="${1:A}"
  local label="$2"
  print -r -- "$label" > "$base/.menubar_label"
}

mn_legacy_menubar_label() {
  print -r -- "com.moxiuwen.meetingnotes.menubar"
}
