# geet

A native macOS 26 menu bar player for collecting YouTube playlists, mixes, and live radio.

[Download for Apple silicon](https://github.com/ArsalanDotMe/geetapp/releases/latest/download/geet-apple-silicon.dmg) · [Website](https://geet.mashaltech.ee) · [Release notes](https://github.com/ArsalanDotMe/geetapp/releases/latest)

Open the DMG, drag geet to Applications, then open it. The Listener icon appears in your menu bar. Public releases are Developer ID signed and notarized by Apple.

## Run

The local development app is `build/Geet.app`. Open it, then click the Listener icon in your menu bar. Use **+** to add a public or unlisted YouTube playlist or video. Play resumes each collection’s saved track and position. The arrow beside a playlist opens its individual tracks. Right-click the menu bar icon and choose **Quit geet** to close the app.

The [brand guide](Design/Branding/README.md) defines Newsreader for geet's name and editorial headings. The Listener logo stays text-free; native macOS fonts are retained for controls and body text.

The first launch opens no windows, performs no network requests, creates no player, and starts no helper processes. yt-dlp is checked lazily on the first operation that needs it. Login launch behaves the same way.

## Build

Requires macOS 26+, Xcode 26 or newer with a Swift 6.2+ toolchain, and Python 3 for the optional dependency bootstrap. This build was verified on Apple Silicon with Xcode 27.1 and macOS 26.6.2.

```sh
python3 scripts/bootstrap-tools.py
zsh scripts/build.sh
open build/Geet.app
```

The bootstrap downloads upstream yt-dlp and Deno releases, verifies their published SHA-256 digests, and records their versions in `scripts/tools-lock.json`. Helpers are bundled when building; the app never installs or updates them at launch. An installed yt-dlp is preferred, including Homebrew’s `/opt/homebrew/bin` and `/usr/local/bin` locations, because the bundled standalone launcher can take substantially longer to start. If extraction with the installed copy fails, geet retries with its bundled helper. `GEET_YTDLP` can select an explicit executable. Deno handles YouTube’s JavaScript challenges. No Homebrew installation is needed for the prepared app.

```sh
zsh scripts/build.sh release
```

This produces `build/Release/Geet.app`. Development builds are locally ad-hoc signed. The [release process](docs/releasing.md) creates and verifies a Developer ID signed, notarized Apple silicon DMG. Intel builds and distribution have not been validated.

## Listening and offline storage

- Streaming is free. Playlist options include play from the beginning, keep offline, refresh, move to top, and remove.
- Shuffle preserves a stable order and track occurrences. Repeat cycles through off, playlist, and track. MediaPlayer integrates play/pause, previous/next, seeking, and Now Playing artwork with macOS.
- Explicit offline downloads and the optional listening cache share range-based audio storage. Audio is not downloaded a second time for caching. Partial files are not presented as complete offline downloads. Live radio stays online only.
- The listening cache is limited to 2 GB; all saved audio is limited to 10 GB and 2,048 entries. Explicitly saved tracks are protected from automatic eviction. Storage is shown in Settings. Stopping offline retention removes files that aren’t shared with another saved playlist.
- A playlist import is limited to its first 1,000 available entries, with a notice when truncated. Private, deleted, and unavailable entries are excluded. Intentional duplicate video occurrences remain in the queue.
- Discover loads curated categories from a public R2 feed, with a validated local cache and bundled fallback. Browse shelves by trackpad or mouse drag, open a category with its arrow, and preview radios, mixes, or playlists without saving them. Add to library is separate. See [Discover publishing](Discover/README.md). Provider links can still be removed or restricted.

Offline listening will be unlocked by a one-time $5 contribution. **Debug builds enable it for development; release builds keep it locked until checkout is integrated.** The support screen says checkout is coming soon. No purchase or entitlement is written to the user’s library.

## Resource lifecycle

| Area | Limit or behavior |
| --- | --- |
| Progress | A 0.5-second AVPlayer observer exists only while playing with the panel open. Closing destroys the SwiftUI tree and removes the observer. Now Playing time is extrapolated by macOS, without app polling. |
| Pause | One cancellable deadline releases the entire media pipeline after 600 seconds. No repeating idle timer exists. Play recreates it using saved audio or a valid stream URL. An expired YouTube URL requires a fresh resolve. |
| Dependencies | Version and file fingerprint are persisted for 24 hours. Cached checks use file attributes without launching a process. Recheck forces a probe. |
| Resolver | A single process lane covers probes, metadata imports, resolves, and look-ahead. Foreground demand cancels speculative work and waits for its exit before starting. Concurrent requests for one stream are coalesced. |
| Failures | Failed links are cooled down for ten minutes. Automatic playback recovery is limited to two attempts per track. There is no periodic retry task. |
| Look-ahead | The next queue item is resolved once per track. Clipboard inspection happens on panel opening only, with no clipboard polling. |
| Streams | At most 64 valid stream descriptions are retained. Signed stream URLs remain local. |
| Audio memory | At most six 512 KB audio chunks, plus bounded in-flight range responses and AVPlayer’s native buffer. |
| Artwork | At most 24 decoded network images within 24 MB, plus bounded bundled fallback artwork. Disk artwork is capped at 64 MB and 128 images. Offscreen cells release image state. |

The app prefers native AAC audio and audio-only HLS. For older extractors that expose only muxed live HLS, the lowest-bandwidth native rendition is the final fallback and video tracks are disabled. Normal recorded playback never requests a video format.

For indexed DASH AAC, geet maps the existing fragment index to a small, immutable HLS playlist on a private loopback endpoint. Encoded audio is unchanged. This gives AVPlayer accurate duration and direct seeking without scanning or downloading an entire long mix. The listener binds only to `127.0.0.1`, uses a random path, accepts at most four connections, and is released with the player. Free streaming keeps chunks in bounded memory; disk retention requires the offline entitlement and an explicit cache or download choice.

## Privacy and dependencies

Library data and local caches live in `~/Library/Application Support/Geet`. Cloudflare receives requests for the public Discover feed. YouTube and its media/image hosts receive requests needed for the links you use. Clipboard links are only read when opening the panel. No browser cookies, credentials, or private accounts are imported.

geet's own code is [MIT licensed](LICENSE). yt-dlp, Deno, fonts, and third-party assets retain their own licenses. See [third-party notices](THIRD_PARTY_NOTICES.md) and [corresponding source directions](licenses/SOURCES.md).
