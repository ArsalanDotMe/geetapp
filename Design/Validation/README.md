# Native validation

Validated on 21 October 2026 using macOS 26.6.2, Apple Silicon, and Xcode 27.1.

## Build and source checks

- Debug and optimized release builds succeeded.
- Both app bundles passed `codesign --verify --deep --strict`. They are ad-hoc signed, not notarized.
- 22 automated tests passed across six suites. These cover queue/history/repeat semantics, URL normalization, unavailable and duplicate entries, process serialization and preemption, request coalescing, persisted dependency validation, failure cooldowns, and bounded/corrupt audio caches.
- `popover-check.json` confirms that the actual status-item popover and its native window were visible. Initial presentation waits for status-item hosting to finish after launch; normal menu bar clicks present immediately.

## Real playback

`runtime-validation.json` records the final acceptance run. Every behavioral check passed:

- Import a real public playlist with 19 available tracks and a separate public video.
- Resolve and play the remote audio using AVPlayer, with its playback clock advancing and its time-control status playing.
- Attach the progress observer when the panel is open and remove it when closed.
- Release the pipeline after the paused deadline, then rebuild it from a cached stream without another yt-dlp operation. The test injects a 0.25-second deadline into the same scheduler that uses 600 seconds in production.
- Save audio and play it through the native resource loader without network requests or yt-dlp operations.
- Advance automatically to the next queue occurrence, complete repeat-one with a newly created player item, and wrap repeat-all.
- Play the real Lofi Girl live audio-only HLS stream.
- Finish with the media pipeline released and the audio-memory cache within its fixed limit.

The first phase explicitly disables offline file selection so a repeated test run cannot mistake cached playback for a successful streaming test. The offline phase enables the development entitlement and verifies request counters remain unchanged.

## Resource measurements

`idle-measurement.json` records the final 15-second sample after launch, with the panel closed:

| Measurement | Result |
| --- | --- |
| Process CPU time | 0.002543 seconds |
| Average process CPU | 0.01695% |
| Resident memory before / after | 70,631,424 / 70,500,352 bytes |
| Progress observers | 0 |
| Media pipelines | 0 |
| Resolver process starts | 0 |

The final five-second closed-panel playback sample measured 1.0485% process CPU. Short playback samples across earlier warm and cold runs ranged from about 0.61% to 6.88%, including initial media initialization. These are process-level samples, not long-duration battery or whole-system energy measurements. They exclude CPU time in child extractors. No claim is made that every new YouTube link takes a fixed number of seconds to resolve.

## Visual review

The selected reference is `../References/option-2-cover-stories.png`. Native captures were reviewed for the playlist-led hierarchy, artwork bands, playlist Play buttons, secondary track browsing, typography, spacing, and persistent transport. Featured-title clipping and menu-control alignment were corrected during review.

- `native-library-light.png` and `native-library-dark.png`: actual menu bar popover with native glass, both appearances.
- `native-discover.png`: real publisher artwork and bundled verified selections.
- `native-settings.png`: storage, login, dependency, and development-entitlement controls.
- `native-add-link.png`: focused native text input and add flow.
- `native-tracks.png`: secondary track list.

Visual fixtures are isolated, debug-only sample data. Normal launches start with the real persisted library and do not insert fictional playlists. The screenshot itself is never used as an application surface. Native controls honor macOS appearance, accent, focus, scrollbar, and accessibility preferences.

## Remaining acceptance

Physical keyboard/headset media commands, login-item approval, real unlisted content, Intel hardware, and a long-running battery test still need device acceptance. MediaPlayer commands and Now Playing artwork are implemented; physical-key acceptance is not inferred from API registration. Real checkout, Developer ID signing, hardened-runtime distribution checks, and notarization remain outside this development milestone.
