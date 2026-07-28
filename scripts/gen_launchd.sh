#!/bin/zsh
set -eu

SCRIPT_DIR="${0:A:h}"
TEMPLATE="$SCRIPT_DIR/../launchd/com.meetingnotes.plist.template"
project_arg="${1:?用法: gen_launchd.sh <project_dir>}"
project_dir="${project_arg:a}"

if [[ ! -f "$TEMPLATE" ]]; then
  print -u2 -- "找不到 launchd 模板: $TEMPLATE"
  exit 1
fi

path_hash="$(printf '%s' "$project_dir" | shasum | cut -c1-8)"
label="com.meetingnotes.$path_hash"

xml_escape() {
  print -r -- "$1" |
    sed -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&apos;/g"
}

escaped_project="$(xml_escape "$project_dir")"
plist="$(<"$TEMPLATE")"
plist="${plist//__LABEL__/$label}"
plist="${plist//__PROJECT__/$escaped_project}"
print -r -- "$plist"
