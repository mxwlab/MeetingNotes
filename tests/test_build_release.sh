#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$ROOT/build_release.sh" test-build "$tmp/one" >/dev/null
"$ROOT/build_release.sh" test-build "$tmp/two" >/dev/null

zip_one="$tmp/one/MeetingNotes-mac-test-build.zip"
zip_two="$tmp/two/MeetingNotes-mac-test-build.zip"
cmp "$zip_one" "$zip_two" || { echo "FAIL non-reproducible zip"; exit 1; }

listing="$tmp/listing.txt"
python3 - "$zip_one" > "$listing" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    for name in archive.namelist():
        print(name)
PY
python3 - "$zip_one" <<'PY'
import stat
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    for name in ("MeetingNotes/开始使用.command", "MeetingNotes/scripts/bootstrap_mac.sh"):
        mode = archive.getinfo(name).external_attr >> 16
        if not stat.S_ISREG(mode):
            raise SystemExit(f"not a regular file: {name}")
        if not mode & stat.S_IXUSR:
            raise SystemExit(f"not executable: {name}")
PY
for required in \
  'MeetingNotes/开始使用.command' \
  'MeetingNotes/scripts/bootstrap_mac.sh' \
  'MeetingNotes/process.py' \
  'MeetingNotes/scripts/provision_models.sh' \
  'MeetingNotes/scripts/provision_menubar.sh' \
  'MeetingNotes/scripts/install_menubar_autostart.sh' \
  'MeetingNotes/requirements-ui.txt' \
  'MeetingNotes/setup_ui.py' \
  'MeetingNotes/ui/menubar.py' \
  'MeetingNotes/ui/pet_status.py' \
  'MeetingNotes/ui/provider_config.py' \
  'MeetingNotes/launchd/com.moxiuwen.meetingnotes.menubar.plist.template'; do
  grep -Fqx "$required" "$listing" || { echo "FAIL missing $required"; exit 1; }
done
if grep -Fqi 'fluidaudio' "$listing"; then
  echo "FAIL FluidAudio should no longer be packaged"; exit 1
fi

if grep -E '(^|/)(\.git|config\.local\.sh|venv|runtime|models|tools|inbox|output|done|logs|__pycache__)(/|$)' "$listing"; then
  echo "FAIL forbidden path in release"
  exit 1
fi
if grep -E '\.(m4a|mp3|mp4|aac|flac)$' "$listing"; then
  echo "FAIL user audio in release"
  exit 1
fi

unpacked="$tmp/unpacked"
python3 - "$zip_one" "$unpacked" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2])
PY
if rg -l --hidden --glob '!config.example.sh' \
  'DEEPSEEK_API_KEY=[^\"'\"'[:space:]]{8,}|sk-[A-Za-z0-9_-]{12,}' \
  "$unpacked/MeetingNotes"; then
  echo "FAIL possible secret in release"
  exit 1
fi

(cd "$tmp/one" && shasum -a 256 -c MeetingNotes-mac-test-build.zip.sha256) >/dev/null \
  || { echo "FAIL archive checksum"; exit 1; }
[[ -s "$tmp/one/MeetingNotes-mac-test-build.manifest.txt" ]] \
  || { echo "FAIL manifest"; exit 1; }

if command -v ditto >/dev/null; then
  native_unpack="$tmp/native-unpacked"
  mkdir -p "$native_unpack"
  ditto -x -k "$zip_one" "$native_unpack"
  [[ -x "$native_unpack/MeetingNotes/开始使用.command" ]] \
    || { echo "FAIL macOS native extraction dropped launcher executable mode"; exit 1; }
  [[ -x "$native_unpack/MeetingNotes/scripts/bootstrap_mac.sh" ]] \
    || { echo "FAIL macOS native extraction dropped bootstrap executable mode"; exit 1; }
fi

echo "PASS"
