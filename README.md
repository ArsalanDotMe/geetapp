# Geet

A native macOS 26 menu bar player for collecting YouTube playlists, long mixes, and live radio. SwiftUI and AppKit provide the interface, `AVPlayer` plays audio, and yt-dlp resolves links behind the scenes. No browser player, account, analytics, or web UI is embedded in the app.

## Run

The local development app is `build/Geet.app`. Open it, then click the waveform in your menu bar. Use **+** to add a public or unlisted YouTube playlist or video. Play resumes each collection’s saved track and position. The arrow beside a playlist opens its individual tracks. Right-click the menu bar icon and choose **Quit geet** to close the app.

The first launch opens no windows, performs no network requests, creates no player, and starts no helper processes. yt-dlp is checked lazily on the first operation that needs it. Login launch behaves the same way.

## Build

Requires macOS 26+, Xcode 26 or newer with a Swift 6.2+ toolchain, and Python 3 for the optional dependency bootstrap. This build was verified on Apple Silicon with Xcode 27.1 and macOS 26.6.2.

```sh
python3 scripts/bootstrap-tools.py
zsh scripts/build.sh
open build/Geet.app
```

The bootstrap downloads upstream yt-dlp and Deno releases, verifies their published SHA-256 digests, and records their versions in `scripts/tools-lock.json`. Helpers are bundled when building; the app never installs or updates them at launch. Without bundled helpers, a local yt-dlp installation is supported, including Homebrew’s `/opt/homebrew/bin` and `/usr/local/bin` locations. Deno handles YouTube’s JavaScript challenges. No Homebrew installation is needed for the prepared app.

```sh
zsh scripts/build.sh release
```

This produces `build/Release/Geet.app`. Both builds are locally ad-hoc signed. Public distribution still needs Developer ID signing, notarization, and hardened-runtime validation for the bundled helpers. Intel builds and distribution have not been validated.

## Listening and offline storage

- Streaming is free. Playlist options include play from the beginning, keep offline, refresh, move to top, and remove.
- Shuffle preserves a stable order and track occurrences. Repeat cycles through off, playlist, and track. MediaPlayer integrates play/pause, previous/next, seeking, and Now Playing artwork with macOS.
- Explicit offline downloads and the optional listening cache share range-based audio storage. Audio is not downloaded a second time for caching. Partial files are not presented as complete offline downloads. Live radio stays online only.
- The listening cache is limited to 2 GB; all saved audio is limited to 10 GB and 2,048 entries. Explicitly saved tracks are protected from automatic eviction. Storage is shown in Settings. Stopping offline retention removes files that aren’t shared with another saved playlist.
- A playlist import is limited to its first 1,000 available entries, with a notice when truncated. Private, deleted, and unavailable entries are excluded. Intentional duplicate video occurrences remain in the queue.
- Discover contains a small bundled selection verified against public Lofi Girl and Chillhop sources on 21 October 2026. It is curated, not a live popularity ranking. Streams can be removed or restricted by their providers.

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

For indexed DASH AAC, Geet maps the existing fragment index to a small, immutable HLS playlist on a private loopback endpoint. Encoded audio is unchanged. This gives AVPlayer accurate duration and direct seeking without scanning or downloading an entire long mix. The listener binds only to `127.0.0.1`, uses a random path, accepts at most four connections, and is released with the player. Free streaming keeps chunks in bounded memory; disk retention requires the offline entitlement and an explicit cache or download choice.

## Validation

```sh
zsh scripts/test.sh
```

The 31 tests cover link normalization, queue history and repeat, duplicate entries, bounded metadata, resolver serialization and preemption, shared resolves, dependency cache reuse, failure cooldowns, disk-cache integrity, shared-download cancellation, memory-only streaming, DASH fragment indexing, initialization headers, and HTTP byte ranges.

Debug-only runtime checks use isolated data, muted playback, real public YouTube content, and the actual native player:

```sh
GEET_VALIDATION_DIR="$PWD/build/runtime-validation" \
GEET_DATA_DIR="$PWD/build/runtime-app-data" \
build/Geet.app/Contents/MacOS/Geet --validate-runtime
```

Additional debug checks are `--validate-library`, `--validate-audio`, and `--verify-deep-idle`. Use a fresh isolated `GEET_DATA_DIR` and `GEET_VALIDATION_DIR` for each run. Library acceptance starts empty and exercises real store actions, all four Discover choices, offline playback, persistence, refresh, and cancellation. Supply an unlisted playlist through `GEET_UNLISTED_URL`; it is excluded from the shareable report and captures. The audio check measures a two-hour mix, verifies duration and playback speed, then seeks near its end without downloading intervening audio.

The paused deadline was also exercised over the actual 600 seconds, with no additional helpers and a successful warm resume. The short runtime suite injects a 0.25-second deadline for repeatable teardown checks. Offline playback is checked with unchanged outbound request and helper counters. Native Accessibility testing covers actual clicks and keyboard input. The owner separately confirmed audible playback, hardware Play/Pause and Next, and menu-bar panel close/reopen. These checks do not substitute for a long-running battery measurement.

The [selected design](Design/References/option-2-cover-stories.png) is retained for future reference. The [completion review](Design/Validation/Completion/README.md) contains fresh native captures, the independent design critique, runtime evidence, and acceptance limits. [Initial validation](Design/Validation/README.md) is retained as historical evidence. `--design-preview` uses a separate, in-memory fixture library solely for design review; no sample playlists are inserted into the real library. It and the runtime/interaction harnesses are excluded from release builds.

## Privacy and dependencies

Library data and local caches live in `~/Library/Application Support/Geet`. YouTube and its media/image hosts receive requests needed for the links you use. Clipboard links are only read when opening the panel. No browser cookies, credentials, or private accounts are imported.

yt-dlp and Deno are third-party dependencies. Their upstream licenses and redistribution requirements apply, including the components packaged in the yt-dlp binary. See [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [Deno](https://github.com/denoland/deno). This project does not claim YouTube API approval.
