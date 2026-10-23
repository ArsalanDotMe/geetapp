# Discover feed

The public feed is served from [geet.mashaltech.ee/discover/v1.json](https://geet.mashaltech.ee/discover/v1.json) by the dedicated `geet-discover` R2 bucket. The custom domain requires TLS 1.2 or newer. No credentials are shipped in the app.

## Updating the feed

Run these commands from the repository root. You need Swift/Xcode command-line tools, Node.js with npm, Python 3, and curl.

1. Edit `Sources/GeetCore/Resources/discover-v1.json`. Keep category and item IDs stable when changing titles or order. Check every provider link by playing it, including whether a Radio is still live. Schema validation cannot detect a deleted, restricted, or ended stream.
2. Validate locally without accessing Cloudflare:

   ```sh
   zsh scripts/publish-discover.sh --check
   ```

3. Publish:

   ```sh
   zsh scripts/publish-discover.sh
   ```

4. Open Discover and use its refresh button to check the updated content. Commit the manifest change so future app builds carry the same fallback:

   ```sh
   git add Sources/GeetCore/Resources/discover-v1.json
   git commit -m "Update Discover selections"
   ```

The publisher uses the app's decoder, then saves the current valid public manifest under the ignored `build/discover-backups/` directory before uploading. It sets `application/json` and `public, max-age=0, must-revalidate`, then downloads the public object, validates it, and compares its bytes with the input. Any failure exits nonzero. An invalid local manifest or an unreadable current public feed stops before upload. A failure after upload may mean the new object is already live; check the public URL and roll back if needed.

Wrangler is pinned in the script. If its saved login expires, run `npx --yes wrangler@4.151.3 login`, complete authentication yourself, and retry. The account needs R2 object write access. Never put credentials or private links in the manifest; the entire bucket is publicly readable through its custom domain.

You can validate or publish another file by supplying its path, for example `zsh scripts/publish-discover.sh --check build/candidate.json`. Publishing does not rebuild or release the installed app. The JSON in the repository is also the bundled fallback used before the first successful remote fetch. Keep it current with published edits.

## Rolling back

Publish the backup printed by the previous run:

```sh
zsh scripts/publish-discover.sh build/discover-backups/TIMESTAMP-PID.json
```

Replace that example filename with the actual backup path. Backups are local and disappear when `build/` is removed. Git is the durable history. To restore a committed version, substitute a known good commit for `GOOD_COMMIT`:

```sh
mkdir -p build
git show GOOD_COMMIT:Sources/GeetCore/Resources/discover-v1.json > build/discover-rollback.json
zsh scripts/publish-discover.sh build/discover-rollback.json
```

After verification, copy the restored JSON back to `Sources/GeetCore/Resources/discover-v1.json` and commit it. Valid but undesirable edits are not automatically rolled back. Existing clients keep their last valid data if a later response is malformed, but a valid editorial mistake needs a corrected publish.

## Hosting configuration

The deployed bucket is `geet-discover`, object key `discover/v1.json`, in the Cloudflare account pinned by `wrangler.jsonc`. `hosting.json` records the bucket, key, domain, and public URL. The custom domain `geet.mashaltech.ee` has active ownership and TLS, with TLS 1.2 as its minimum. The alternate `r2.dev` URL is disabled. There is no Worker, database, or edge Cache Rule. Keep this bucket dedicated to public Discover content.

Inspect the existing setup with:

```sh
npx --yes wrangler@4.151.3 --config Discover/wrangler.jsonc r2 bucket info geet-discover
npx --yes wrangler@4.151.3 --config Discover/wrangler.jsonc r2 bucket domain get geet-discover --domain geet.mashaltech.ee
npx --yes wrangler@4.151.3 --config Discover/wrangler.jsonc r2 bucket dev-url get geet-discover
curl -I https://geet.mashaltech.ee/discover/v1.json
```

Expect an active custom domain, disabled development URL, HTTP 200, JSON content type, an ETag, and the revalidation cache policy. An `If-None-Match` request with that ETag should return 304 when the object is unchanged. Don't add a cache rule that ignores revalidation unless you also provide a cache purge step for publishing.

`scripts/build.sh` embeds the public URL in `GeetDiscoverFeedURL` in the application's Info.plist. Set `GEET_DISCOVER_URL` at build time to use another HTTPS endpoint. Debug builds also accept it at runtime for isolated checks. Changing the hostname, object path, or supported schema requires coordinating an app update. Ordinary category and item edits do not. Keep schema version 1 available for installed clients until a migration is complete.

## Format

```json
{
  "schemaVersion": 1,
  "categories": [
    {
      "id": "on-the-air",
      "title": "On the air",
      "subtitle": "Live company for your day",
      "items": [
        {"id": "lofi", "title": "Halloween lofi radio", "creator": "Lofi Girl", "kind": "Radio", "videoID": "0sfDth4lMLc"},
        {"id": "study", "title": "Chill Study Beats 7", "creator": "Chillhop Music", "kind": "Mix", "videoID": "mypnwpywaaw"},
        {"id": "classroom", "title": "Chillhop in the Classroom", "creator": "Chillhop Music", "kind": "Playlist", "videoID": "mypnwpywaaw", "playlistID": "PLt7bG0K25iXhu8bSbLsoWFBf-xSyLwy2_"}
      ]
    }
  ]
}
```

There must be 1–5 categories with 3–10 items each. Category IDs are unique in the feed; item IDs are unique within each category. The same item can appear in several categories. IDs use letters, numbers, hyphens, and underscores, up to 80 characters. A category title is required; omit `subtitle` when it isn't needed. Empty subtitles are rejected. Category titles allow 100 characters, subtitles 180, item titles 120, creators 100, and mood descriptions 180. Display strings cannot be blank or contain control characters. `mood` is an optional item description retained for compatibility.

`kind` is exactly `Radio`, `Mix`, or `Playlist`. Every item requires a valid 11-character YouTube `videoID`, used for its artwork. `Playlist` also requires `playlistID`. `Mix` may be a continuous video or have a playlist ID, including a YouTube mix ID. `Radio` is a live-video link and cannot have a playlist ID. The supplied label is editorial; verify that a radio really is live before publishing it. Artwork comes from YouTube; playback still uses the existing resolver. The example mixes types in one category, which the renderer supports.

Array order controls both category and item order. Shelves scroll horizontally by trackpad, Shift-wheel, keyboard arrows, or mouse drag. The heading's arrow opens that category's grid; Back restores the previous shelf position. Search matches category titles/subtitles and item titles, creators, and types.

## Refresh and playback

The app checks the feed when Discover opens if its last successful check was more than 30 minutes ago. The refresh button checks immediately. ETag and Last-Modified headers avoid unnecessary downloads. Only validated HTTP 200 JSON or a valid 304 response updates the cache. Failed requests and malformed updates leave the last valid feed in place. Responses are bounded to 256 KiB; unsupported schema versions are rejected. The cached feed belongs to its exact endpoint and persists across launches. Nothing fetches at menu-bar-only startup.

Play creates a temporary playback collection with a separate identity. Previewing never adds to or selects an item in the saved library. Add is explicit; adding a loaded preview saves a copy without restarting its audio or queue. Only saved collections persist after relaunch. The transport's queue button can show the current preview's tracks.

## Verification

```sh
zsh scripts/test.sh
GEET_BUILD_DESTINATION="$PWD/build/Discover/Geet.app" zsh scripts/build.sh
GEET_DATA_DIR="$PWD/build/discover-acceptance/data" \
GEET_VALIDATION_DIR="$PWD/build/discover-acceptance/evidence" \
build/Discover/Geet.app/Contents/MacOS/Geet --validate-discover --appearance light
```

Use a fresh data directory for each acceptance run. The debug-only harness plays muted public radio/mix/playlist streams and checks preview cancellation and library persistence. Interaction checks use the separate native Accessibility helper described in `scripts/testing/README.md`. It does not change system input permissions. Real playback depends on the public providers and network being available.
