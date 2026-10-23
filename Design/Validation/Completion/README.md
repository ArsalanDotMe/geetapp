# Completion review

Checked on 21 October 2026 on Apple Silicon, macOS 26.6.2, Xcode 27.1. The app is native SwiftUI/AppKit with an actual status-item popover and AVPlayer playback. Debug builds enable offline development; release builds keep offline listening disabled.

## Visual review

The selected [Cover Stories reference](../../References/option-2-cover-stories.png) remains the design anchor: artwork-led playlist collection, direct playlist Play actions, secondary track browsing, quiet sage accents, and persistent transport. Native platform controls and appearance preferences take precedence over painted replicas of controls in the reference.

The initial review used [Library](01-library-before.png) and [Discover](02-discover-before.png) captures. The final captures below come from the actual native app with an isolated library, real public YouTube metadata, and real playback. They were inspected individually. No screenshot is used as an application surface.

| Step | Native evidence | What was inspected |
| --- | --- | --- |
| 1 | [Empty library](03-empty-library.png) | Clear Add and Discover entry points, no invented saved content. |
| 2 | [Add link](04-add-link.png) | Focused native text field, clear close action, background interaction disabled. |
| 3 | [Library playing](05-library-playing.png) | Playlist-led hierarchy, clear Play/Pause action, current collection indicator, accurate 19-second duration. |
| 4 | [Current track](06-current-track.png) | Current row, long-title wrapping, identical 2:00:37 row and transport durations, readable central control. |
| 5 | [Settings while playing](07-settings-with-transport.png) | Controls and storage explanations fit; transport stays accessible. |
| 6 | [Discover while playing](08-discover-saved.png) | Play buttons read as enabled, saved checkmarks are visible, playing card shows Pause. |
| 7 | [Library search](09-library-search.png) | Search filters collections while preserving playlist Play and transport. |

The fresh [light appearance](final-library-light.png) also uses isolated fixtures to compare the selected layout with native controls. Earlier `after-*` captures use isolated design fixtures. They document layout iteration, not playback acceptance.

An independent read-only design reviewer compared the implementation with the selected reference and re-reviewed the final actual-playback captures. Its concrete findings were resolved:

| Finding | Correction | Final evidence |
| --- | --- | --- |
| Discover Play looked disabled | Dark glyph on a clear light circular action | Step 6 |
| Saved and playing Discover states were unclear | Saved checkmark and matching Play/Pause/loading state | Step 6 |
| Search was offered where it did not work | Filter both collection tabs; hide it in track detail | Steps 4 and 7; source and interaction checks |
| Current track and playlist were hard to locate | Static waveform and current-row highlight | Steps 3 and 4 |
| Small icon hit areas | Frames inside labels, content shapes, explicit accessible labels | Source and native Accessibility checks |
| Settings hid playback controls | Common transport outside the route-specific content | Step 5 |
| Transport doubled a recorded mix's duration | Map DASH fragment timing to native VOD HLS | Step 4 and audio acceptance |
| White central glyph lacked contrast in dark appearance | Dark glyph on the lighter sage button | Steps 4 to 6 |

The final reviewer found no blocking visual issue in Steps 4 to 6. Its minor finding about soft enlarged thumbnails was also addressed: matching playlist covers now reuse the first track's already-resolved sharper image, and all four curated Discover covers use verified higher-resolution sources. This adds no resolver work and preserves the existing image cache limits. Distinct playlist covers remain intact. Fresh actual-playback [track detail](final-track-artwork.png) and [Discover](final-discover-artwork.png) captures show the improvement. The independent reviewer confirmed sharper artwork with no remaining blocking issue evident in those screenshots. This review is screenshot evidence, not a full accessibility conformance assessment. Reduced Motion uses native preference checks; physical assistive-technology acceptance remains separate.

## Functional acceptance

[Library acceptance](library-validation.json) records successful checks for an empty first launch, invalid and duplicate links, a real public video and playlist, moving collections, persistence across a new store instance, Now Playing metadata, exact seek/pause/resume positions, offline saving/playback/removal, pinned-cache protection, and removing the playing collection.

All four curated Discover entries were imported and played through the native player: Lofi Girl live radio, Classroom with 19 available entries, Fall with 12, and Winter with 10. Shuffle advanced to another queue occurrence and Previous restored its history. Refresh preserved resume state and ordering. Cancelling an import left no busy state. The supplied unlisted playlist imported and played successfully. Its URL, identifier, titles, stream descriptions, and screenshots are intentionally absent from the committed evidence.

The separate runtime suite checks automatic advancement, repeat-one, repeat-all, live radio, offline playback, panel clock attachment/removal, and accelerated teardown using the same production lifecycle. Test modes return a nonzero exit code on failed acceptance.

[Native interaction results](interaction-validation.json) confirm focused Add input, inaccessible background controls while the form is open, actual typed input and Return importing a new collection, the playlist Play button, and Space pausing/resuming with the corresponding progress-observer state. These use actual Accessibility and keyboard input rather than calling store methods. Volume unmute was exercised through the native popover. Status-item AXPress did not toggle the panel on this machine; the owner separately verified the real menu-bar close/reopen interaction.

## Resource acceptance

The long-mix check uses an actual two-hour public recording. It checks AVPlayer duration against resolved metadata, compares playback-clock advancement with elapsed wall time, samples CPU and resident memory, enforces the six-chunk memory bound, verifies streaming leaves disk audio empty, and seeks near the end using only the required fragments. The [audio report](audio-validation.json) measured 7,237.427 seconds of native duration, three range requests over a 31.17-second sample, 0.737% average process CPU, and resident memory from 89.5 to 90.8 MB. Both the near-end seek and its bounded-request check passed. The [final runtime report](runtime-validation.json) passed every behavioral check, with a separate five-second closed-panel playback sample of 0.666% CPU.

Recorded AAC is exposed to AVPlayer as an immutable HLS playlist built from its DASH segment index. Initialization durations are normalized, preserving encoded samples and fragment byte offsets. This avoids the doubled duration and whole-file probing seen with the original direct/custom-loader path. No transcoder or persistent server process is introduced. The private loopback listener exists only with the media pipeline.

[Real ten-minute pause](deep-idle-validation.json) retained the pipeline at its measured 540.7-second checkpoint, released it after 603.7 seconds, launched no helpers while paused, and resumed using the warm stream cache without another helper. That production-deadline run preceded the transport replacement; the final transport is separately checked through the same accelerated teardown path and ends with no pipeline or progress observer.

The [final 15-second idle measurement](idle-measurement.json) used 0.000958 seconds of CPU, averaging 0.00639%, with resident memory from 70.9 to 70.7 MB. It recorded zero helper starts, pipelines, and progress observers. No process starts at initialization. The 24-hour dependency cache uses executable file attributes, and Recheck forces a probe. Resolver tests enforce serialization, foreground preemption, shared resolves, cooldowns, and bounded recovery. Stream and artwork cache limits remain fixed. Idle and playback CPU samples describe this process on this machine; they exclude child extractor work and are not whole-system battery measurements.

## Build and remaining device checks

[Build evidence](build-validation.json) records the source commit and executable digests. All 31 automated tests in nine suites passed. Debug and optimized release builds succeeded and passed strict deep ad-hoc signature verification. Release executable inspection found no debug preview, library-validation, or interactive-test entry points.

The [owner's device acceptance](device-validation.json) confirms audible music, hardware Play/Pause and Next, and menu-bar panel close/reopen in the running native app. This covers the owner's available keyboard or headset, not every hardware model. The subsequent artwork-only refinement did not change playback or media command handling. Login-item approval, Intel hardware, long-duration battery measurement, Developer ID signing, hardened-runtime helper distribution, and notarization are not inferred from source or screenshot checks.

Native interaction testing uses the owner's explicit Geet-only Accessibility authorization. The helper in `scripts/testing/accessibility.swift` refuses other bundle IDs and executables outside this checkout's build directory. Every injected keyboard event checks that Geet still has focus. Raw Accessibility dumps, key-event logs, private test state, and signed stream URLs stay in ignored `build/` output.
