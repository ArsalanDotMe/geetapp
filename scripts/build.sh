#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-debug}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox -c "$configuration"
products="$(swift build --disable-sandbox -c "$configuration" --show-bin-path)"
destination="${GEET_BUILD_DESTINATION:-$PWD/build/Geet.app}"
if [[ "$configuration" == release && -z "${GEET_BUILD_DESTINATION:-}" ]]; then destination="$PWD/build/Release/Geet.app"; fi
[[ "$destination" == *.app && "$destination" != /Applications/* ]] || { echo "Use a staging .app destination" >&2; exit 1; }
rm -rf "$destination"
mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources"
cp "$products/Geet" "$destination/Contents/MacOS/Geet"
cp -R "$products/Geet_Geet.bundle" "$destination/Contents/Resources/"
cp -R "$products/Geet_GeetCore.bundle" "$destination/Contents/Resources/"
cp scripts/Info.plist "$destination/Contents/Info.plist"
if [[ -n "${GEET_VERSION:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GEET_VERSION" "$destination/Contents/Info.plist"; fi
if [[ -n "${GEET_BUILD_NUMBER:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GEET_BUILD_NUMBER" "$destination/Contents/Info.plist"; fi
feed_url="${GEET_DISCOVER_URL:-$(python3 -c 'import json; print(json.load(open("Discover/hosting.json"))["url"])')}"
/usr/libexec/PlistBuddy -c "Add :GeetDiscoverFeedURL string $feed_url" "$destination/Contents/Info.plist"
if [[ -f Sources/Geet/Resources/Geet.icns ]]; then cp Sources/Geet/Resources/Geet.icns "$destination/Contents/Resources/Geet.icns"; fi
if [[ -d Tools ]]; then
  mkdir -p "$destination/Contents/Resources/Tools"
  for tool in yt-dlp deno; do
    target="$destination/Contents/Resources/Tools/$tool"
    if [[ "$tool" == yt-dlp && -d "Tools/$tool" ]]; then
      [[ -x "Tools/$tool/yt-dlp_macos" && -d "Tools/$tool/_internal" ]] || { echo "Incomplete unpacked yt-dlp bundle" >&2; exit 1; }
      rm -rf "$target"
      cp -R "Tools/$tool" "$target"
    elif [[ -f "Tools/$tool" && -x "Tools/$tool" ]]; then
      rm -rf "$target"
      cp "Tools/$tool" "$target"
    fi
  done
fi
mkdir -p "$destination/Contents/Resources/Licenses"
cp LICENSE THIRD_PARTY_NOTICES.md "$destination/Contents/Resources/Licenses/"
cp -R licenses/. "$destination/Contents/Resources/Licenses/"
codesign --force --deep --sign - "$destination"
echo "$destination"
