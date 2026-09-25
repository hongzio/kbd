#!/bin/sh
# Builds build/kbd.app (ad-hoc signed). No Xcode required.
#   VERSION=0.1.0          bundle version (default: the one in Resources/Info.plist)
#   ARCHS="arm64 x86_64"   universal binary (default: this Mac's architecture only)
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/build/kbd.app"

binaries=""
if [ -z "${ARCHS:-}" ]; then
    swift build --package-path "$root" -c release
    binaries="$(swift build --package-path "$root" -c release --show-bin-path)/kbd"
else
    for arch in $ARCHS; do
        # A scratch path per architecture keeps the native build's cache intact.
        set -- --package-path "$root" -c release --triple "$arch-apple-macosx14.0" --scratch-path "$root/.build/$arch"
        swift build "$@"
        binaries="$binaries $(swift build "$@" --show-bin-path)/kbd"
    done
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# shellcheck disable=SC2086 # one path per architecture
lipo -create -output "$app/Contents/MacOS/kbd" $binaries
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$VERSION" "$app/Contents/Info.plist"
fi
cp -R "$root/Resources/en.lproj" "$app/Contents/Resources/"
swift "$root/scripts/make-icons.swift" "$app/Contents/Resources"

codesign --force --sign - "$app"
echo "built $app"
