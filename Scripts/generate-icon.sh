#!/usr/bin/env bash
# Render Resources/AppIcon.icns from the artwork drawn by generate-icon.swift.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

master="$work/icon-1024.png"
swift Scripts/generate-icon.swift "$master" 1024

iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
sizes=(
	"16 icon_16x16"
	"32 icon_16x16@2x"
	"32 icon_32x32"
	"64 icon_32x32@2x"
	"128 icon_128x128"
	"256 icon_128x128@2x"
	"256 icon_256x256"
	"512 icon_256x256@2x"
	"512 icon_512x512"
	"1024 icon_512x512@2x"
)
for entry in "${sizes[@]}"; do
	read -r pixels name <<<"$entry"
	sips -z "$pixels" "$pixels" "$master" --out "$iconset/$name.png" >/dev/null
done

iconutil -c icns "$iconset" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
