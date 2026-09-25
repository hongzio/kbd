#!/bin/sh
# Publishes kbd <version>: tags main, attaches the universal app to a GitHub release and
# updates the cask in the Homebrew tap from packaging/kbd.rb.
# Usage: sh scripts/release.sh 0.1.0
#   TAP_DIR   hongzio/homebrew-tap clone (default: the one brew uses)
set -eu

version=${1:?usage: release.sh <version>}
root=$(cd "$(dirname "$0")/.." && pwd)
tap=${TAP_DIR:-$(brew --repository hongzio/tap)}
tag="v$version"
zip="$root/build/kbd-$version.zip"

die() {
    echo "release: $*" >&2
    exit 1
}

cd "$root"
[ "$(git branch --show-current)" = main ] || die "not on main"
[ -z "$(git status --porcelain)" ] || die "uncommitted changes"
git fetch -q origin
git merge-base --is-ancestor origin/main main || die "main is behind origin/main"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then die "tag $tag exists"; fi
[ -z "$(git -C "$tap" status --porcelain)" ] || die "uncommitted changes in $tap"
git -C "$tap" pull -q --ff-only
gh auth status >/dev/null 2>&1 || die "gh is not logged in"

make test
VERSION=$version ARCHS="arm64 x86_64" sh scripts/build-app.sh
for arch in arm64 x86_64; do
    lipo build/kbd.app/Contents/MacOS/kbd -verify_arch "$arch" || die "no $arch in the binary"
done
rm -f "$zip"
ditto -c -k --keepParent build/kbd.app "$zip"
sha=$(shasum -a 256 "$zip" | cut -d ' ' -f 1)

git tag -a "$tag" -m "kbd $version"
git push -q origin main "$tag"
gh release create "$tag" "$zip" --title "kbd $version" --generate-notes

mkdir -p "$tap/Casks"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" packaging/kbd.rb >"$tap/Casks/kbd.rb"
git -C "$tap" add Casks/kbd.rb
git -C "$tap" commit -q -m "kbd $version"
git -C "$tap" push -q
echo "released kbd $version"
