#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project/scripts" "$project/mock-bin"
cp "$ROOT/scripts/build_fluidaudio_release_asset.sh" "$project/scripts/"

cat > "$project/scripts/build_fluidaudio_from_source.sh" <<'BUILD'
#!/bin/zsh
base="${0:A:h:h}"
bin="$base/tools/FluidAudio/.build/release/fluidaudiocli"
mkdir -p "${bin:h}"
cat > "$bin" <<'BIN'
#!/bin/zsh
[[ "${1:-}" == "--help" ]] && exit 0
exit 1
BIN
chmod +x "$bin"
BUILD
cat > "$project/mock-bin/swift" <<'EOF'
#!/bin/zsh
exit 0
EOF
cat > "$project/mock-bin/file" <<'EOF'
#!/bin/zsh
echo "$1: Mach-O 64-bit executable arm64"
EOF
cat > "$project/mock-bin/otool" <<'EOF'
#!/bin/zsh
if [[ "$1" == "-l" ]]; then
  cat <<OUT
      cmd LC_BUILD_VERSION
    minos 14.0
OUT
else
  cat <<OUT
$2:
	/usr/lib/libc++.1.dylib (compatibility version 1.0.0)
	/System/Library/Frameworks/CoreML.framework/Versions/A/CoreML (compatibility version 1.0.0)
OUT
fi
EOF
chmod +x "$project/scripts/build_fluidaudio_from_source.sh" "$project/mock-bin"/*

PATH="$project/mock-bin:/usr/bin:/bin" \
  "$project/scripts/build_fluidaudio_release_asset.sh" "$project/dist"

asset="$project/dist/fluidaudiocli-88d6d816-macos14-arm64.gz"
[[ -s "$asset" && -s "$asset.sha256" && -s "$asset.build-info.txt" ]] \
  || { echo "FAIL missing release files"; exit 1; }
(cd "$project/dist" && shasum -a 256 -c "${asset:t}.sha256") >/dev/null \
  || { echo "FAIL checksum"; exit 1; }
grep -q "Minimum macOS: 14.0" "$asset.build-info.txt" \
  || { echo "FAIL minimum macOS"; exit 1; }
grep -q "Architecture: arm64" "$asset.build-info.txt" \
  || { echo "FAIL architecture"; exit 1; }

echo "PASS"
