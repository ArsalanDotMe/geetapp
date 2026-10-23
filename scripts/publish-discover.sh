#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
check_only=false
if [[ "${1:-}" == --check ]]; then check_only=true; shift; fi
if (( $# > 1 )) || [[ "${1:-}" == -* ]]; then
  echo "Usage: zsh scripts/publish-discover.sh [--check] [manifest.json]" >&2
  exit 2
fi
feed="${1:-Sources/GeetCore/Resources/discover-v1.json}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox
products="$(swift build --disable-sandbox --show-bin-path)"
"$products/Geet" --validate-discover-feed "$feed"
if $check_only; then exit 0; fi
bucket="$(python3 -c 'import json; print(json.load(open("Discover/hosting.json"))["bucket"])')"
key="$(python3 -c 'import json; print(json.load(open("Discover/hosting.json"))["key"])')"
url="$(python3 -c 'import json; print(json.load(open("Discover/hosting.json"))["url"])')"
download="$(mktemp -t geet-discover)"
trap 'rm -f "$download"' EXIT
# Keep a validated rollback copy before replacing the public object. If the
# current endpoint cannot be read, stop before changing remote content.
curl --fail --silent --show-error --retry 3 --connect-timeout 10 --max-time 30 "$url" -o "$download"
"$products/Geet" --validate-discover-feed "$download"
mkdir -p build/discover-backups
backup="build/discover-backups/$(date -u +%Y%m%dT%H%M%SZ)-$$.json"
cp "$download" "$backup"
echo "Previous public manifest: $backup"
npx --yes wrangler@4.151.3 --config Discover/wrangler.jsonc r2 object put "$bucket/$key" \
  --remote --file "$feed" --content-type application/json \
  --cache-control 'public, max-age=0, must-revalidate'
curl --fail --silent --show-error --retry 3 --connect-timeout 10 --max-time 30 "$url" -o "$download"
"$products/Geet" --validate-discover-feed "$download"
cmp "$feed" "$download"
echo "Published and verified: $url"
