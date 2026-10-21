#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-debug}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox -c "$configuration"
products="$(swift build --disable-sandbox -c "$configuration" --show-bin-path)"
destination="$PWD/build/Geet.app"
if [[ "$configuration" == release ]]; then destination="$PWD/build/Release/Geet.app"; fi
mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources"
cp "$products/Geet" "$destination/Contents/MacOS/Geet"
cp -R "$products/Geet_Geet.bundle" "$destination/Contents/Resources/"
cp scripts/Info.plist "$destination/Contents/Info.plist"
if [[ -f Sources/Geet/Resources/Geet.icns ]]; then cp Sources/Geet/Resources/Geet.icns "$destination/Contents/Resources/Geet.icns"; fi
if [[ -d Tools ]]; then
  mkdir -p "$destination/Contents/Resources/Tools"
  for tool in yt-dlp deno; do
    if [[ -x "Tools/$tool" ]]; then cp "Tools/$tool" "$destination/Contents/Resources/Tools/"; fi
  done
fi
codesign --force --deep --sign - "$destination"
echo "$destination"
