# Playback startup

Run the offline suite with `zsh scripts/test.sh`. The optional native benchmark
requires YouTube access and runs muted against two public videos, including a
long mix. It uses the app's tool selection: installed yt-dlp first, with the
bundled helper as a fallback. It uses disposable resolver and audio caches and removes them afterward.

```sh
GEET_BENCHMARK_PLAYBACK=1 \
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --disable-sandbox --filter PlaybackStartupTests
```

`STARTUP` measures Play to a native playback clock above 0.1 seconds. Attempt 0
has no resolved URL or audio cache; attempt 1 reuses both. `pipeline_seconds`
includes extraction, the initial audio chunk, and loopback endpoint setup.

`IMPORT` measures single-video import through native playback. The
`duplicate_extraction=true` case deliberately resolves again after importing,
simulating the previous two-extraction flow. Both cases use the current format
selection, so this comparison isolates the redundant extraction rather than
reproducing every detail of the old import implementation.

`NEXT` switches while look-ahead extraction is running, then separately after
both initial chunks are resident. It checks that each queue uses one version
probe, one extraction, and one range request per track, with no audio saved to
disk and no growth beyond the existing six-chunk memory bound.

Playback keeps AVPlayer's automatic stall protection enabled. The recorded-track
forward buffer preference is five seconds; live radio keeps ten seconds. The
512 KB cache format stays unchanged so existing saved audio remains usable.
Look-ahead fetches at most one initial chunk for the next recorded track,
which may be skipped without being played. Pause and track changes cancel it.

Timing varies with YouTube and network conditions. These checks observe native
playback while muted; they do not establish speaker audibility or long-duration
reliability on a slow connection. The existing `--validate-audio` debug app mode
also checks long-mix progression, seeking, bounded transfers, and pipeline cleanup.

## Local measurements, 22 October 2026

Final native startup measurements on this Mac, in seconds:

| Scenario | Bundled tool only | App's installed-tool preference |
| --- | ---: | ---: |
| Cold short track, including initial dependency probe | 23.81 | 1.97 |
| Cold long mix, dependency already checked | 12.20 | 1.91 |
| Next after its initial chunk is resident | 0.33 | 0.33 |

The final installed-tool run measured import-to-play at 2.02 seconds when
reusing extraction, versus 2.95 seconds with a deliberately redundant extraction.
An earlier run measured 1.76 versus 4.30 seconds. These samples establish the
removed process work, but do not establish a fixed speedup under all network
conditions. Warm replay measured 0.29–0.34 seconds. Next during extraction
measured 1.72 seconds without restarting the helper or duplicating audio requests.

The packaged yt-dlp 2026.08.19 took 13.74 seconds in a separate CLI probe,
including 11.93 seconds before its first debug output. The Homebrew 2026.03.17
copy resolved the same long mix in 1.38 seconds, with debug output after 0.24
seconds. This compares the installed tools on this Mac rather than isolating
release versions. An existing persisted bundled dependency probe no longer
overrides the installed-tool preference. If extraction with the installed copy
fails, geet retains its packaged helper as a compatibility fallback.

With the same Homebrew tool, cold Play before buffer changes measured
1.96–2.25 seconds. These samples do not establish an improvement from the smaller
buffer or extractor cache. The clear gains are selecting the faster entry point
on this Mac and removing duplicate single-video extraction. Extractor caching
allows reuse where yt-dlp supports it; its effect was not isolated here.

The optimized app's native audio validation also passed: 30 seconds of long-mix
playback advanced in real time with three range requests, no audio saved to
disk, bounded memory, successful seeking near the end, correct duration, and
pipeline teardown. That run used the bundled tools and the optimized audio path.

Raw local evidence is in ignored `build/startup-investigation/`, including
`selected-tools-native.log`, `bundled-native.log`, and
`audio-validation/audio-report.json`. Signed stream URLs and other extractor
details must stay out of committed evidence.
