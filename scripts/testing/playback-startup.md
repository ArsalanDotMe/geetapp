# Playback startup

Run `zsh scripts/test.sh` for the offline Swift and bootstrap tests. Build with
`zsh scripts/build.sh` to copy the complete unpacked yt-dlp runtime and Deno into
`build/Geet.app`. Bootstrap uses the releases in `scripts/tools-lock.json`;
`python3 scripts/bootstrap-tools.py --update` explicitly selects newer releases.

The optional native benchmark plays two public videos while muted and uses
disposable resolver and audio caches. Run it against the actual packaged tools
with external executable selection disabled and no Homebrew paths:

```sh
env -u GEET_YTDLP -u PYTHONHOME -u PYTHONPATH \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  GEET_BENCHMARK_PLAYBACK=1 \
  GEET_BENCHMARK_TOOLS="$PWD/build/Geet.app/Contents/Resources/Tools" \
  CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
  /usr/bin/swift test --skip-build --disable-sandbox --filter PlaybackStartupTests
```

`STARTUP` measures Play until the native playback clock exceeds 0.1 seconds.
Attempt 0 has no resolved URL or audio cache; attempt 1 reuses both.
`pipeline_seconds` includes extraction, the initial chunk, and loopback setup.
The test asserts that the resolver uses the unpacked executable inside the app
and separately executes bundled Deno with the same restricted helper PATH.

`IMPORT` measures single-video import through playback. The
`duplicate_extraction=true` case deliberately repeats extraction after import,
simulating the previous flow using the current format selection.

`NEXT` switches during look-ahead extraction and after the next track's first
chunk is resident. It checks one version probe and one extraction per queue,
one audio request per track, no disk retention, and the six-chunk memory bound.

The app's `--validate-audio` debug mode also uses bundled-only resolution. It
checks long-mix playback progression for 30 seconds, near-end seeking, duration,
bounded transfers, immediate pause after seeking, and pipeline teardown.

## Measurements, 22 October 2026

The final packaged app used yt-dlp 2026.08.19 and Deno 2.9.8 without Homebrew:

| Scenario | Seconds |
| --- | ---: |
| Cold short track, including dependency probe | 2.02 |
| Cold long mix, dependency already checked | 2.12 |
| Warm replay | 0.32–0.34 |
| Single-video import through playback | 1.99 |
| Next during extraction | 1.93 |
| Next with its initial audio chunk ready | 0.35 |

The same-version one-file bundle previously measured 23.81 seconds for the
short track including its dependency probe, and 12.20 seconds for the long mix.
Repeated `--version` launches took 11.3–11.4 seconds with that packaging;
the unpacked executable took about 0.35 seconds after its first launch.
The unpacked executable's first launch in that experiment still took 11.5
seconds. Cold track measurements do not establish first-ever macOS launch time.
Network conditions also affect extraction, so these are local samples.

The final app passed the 30-second long-mix check with three audio range
requests, no audio saved to disk, bounded memory, successful near-end seeking,
correct duration, and pipeline teardown. All 108 packaged Mach-O files were
inspected for dynamic-library dependencies; none referenced Homebrew or other
external user-installed libraries. The app passed strict code-sign verification.

AVPlayer still protects against stalls automatically. Recorded tracks request
a five-second forward buffer, and live radio keeps ten seconds. Existing 512 KB
offline cache chunks remain unchanged. Look-ahead warms at most one chunk for
the next recorded track and cancels on pause or a different selection.

Raw local evidence is in ignored `build/unpacked-bundle-validation/`, including
`startup.log`, `native-audio/audio-report.json`, `linkage.json`, and `tests.log`.
These tests observe muted native playback rather than speaker audibility or
long-duration behavior on a slow connection. Signed URLs and other extractor
details must stay out of committed evidence.
