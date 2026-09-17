#!/usr/bin/env bash
# Build the universal app bundle and pack it into build/Lyribar-<version>.zip.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

Scripts/build-app.sh --universal

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
archive="build/Lyribar-$version.zip"
rm -f "$archive"
ditto -c -k --keepParent build/Lyribar.app "$archive"

echo "built $archive"
