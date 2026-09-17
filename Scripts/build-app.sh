#!/usr/bin/env bash
# Assemble build/Lyribar.app from the SwiftPM release build.
set -euo pipefail

universal=0
while [ $# -gt 0 ]; do
	case "$1" in
	--universal) universal=1 ;;
	-h | --help)
		echo "usage: $(basename "$0") [--universal]"
		exit 0
		;;
	*)
		echo "unknown option: $1" >&2
		exit 2
		;;
	esac
	shift
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

build_args=(--disable-sandbox -c release)
if [ "$universal" -eq 1 ]; then
	build_args+=(--arch arm64 --arch x86_64)
fi

swift build "${build_args[@]}"
bin_path="$(swift build "${build_args[@]}" --show-bin-path)"

app="build/Lyribar.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$bin_path/Lyribar" "$app/Contents/MacOS/Lyribar"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
	cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$app"

echo "built $app"
