#!/bin/sh
# Builds build/kbd.app (ad-hoc signed). No Xcode required.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/build/kbd.app"

swift build --package-path "$root" -c release
bin=$(swift build --package-path "$root" -c release --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/kbd" "$app/Contents/MacOS/kbd"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp -R "$root/Resources/en.lproj" "$app/Contents/Resources/"
swift "$root/scripts/make-icons.swift" "$app/Contents/Resources"

codesign --force --sign - "$app"
echo "built $app"
