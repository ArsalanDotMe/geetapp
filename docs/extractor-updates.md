# yt-dlp updates

geet downloads the latest stable macOS yt-dlp runtime on launch. It is not
included in the app bundle. Deno remains bundled. A fresh installation needs
access to GitHub before YouTube playback works. Launch setup runs in the
background; the first YouTube request shares that download if it is still
running. Subsequent launches and panel openings check at most once per day.
Failed checks back off for one hour. If an installed executable is missing and
there is no usable fallback, geet retries setup even after a recent successful
check. Settings > Check again bypasses that delay
and clears failed-link cooldowns and cached stream links.

## Verification and installation

The updater requests `https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest`
and accepts only stable, non-draft releases with a numeric date version. It
requires the `yt-dlp_macos.zip` asset, its exact official release download URL,
its declared size, and a SHA-256 digest published by GitHub. Missing digests,
size mismatches, or checksum mismatches fail closed. Metadata is limited to
1 MiB and archives to 96 MiB. Redirects must remain on an explicit list of
GitHub HTTPS hosts. Connections have timeouts; no shell, Homebrew, or Python is
needed.

The published digest verifies the download against GitHub's HTTPS metadata.
This is not an independent upstream signing-key verification and does not
protect against compromise of the upstream repository or GitHub account.

Before system `ditto` extracts the archive, a ZIP preflight rejects escaping
paths, symlinks, special files, duplicate paths, encryption, ZIP64, mismatched
local filenames, excessive entry counts, and runtimes expanding beyond 512 MiB.
Only after verification and extraction does geet run `--version` and require it
to match the advertised release. The complete runtime, including upstream
notices, lives under:

`~/Library/Application Support/Geet/ExtractorUpdates/<UUID>/runtime/`

`state.json` records the current and previous installations, archive checksums,
executable checksums, rejected releases, and check timing. An atomic write to
this file activates an update. Failed or interrupted downloads leave the
installed runtime in place. Executable hashes are checked when first selecting
an installed runtime and whenever its size or modification date changes. The
signed application bundle is never modified. Runtime commands retain
`--no-update`; geet owns installation and rollback.

## Fallback and rollback

A downloaded runtime takes precedence over the legacy bundled and Homebrew
fallbacks. An explicit `GEET_YTDLP` override still takes precedence for debugging.
Production installers contain no bundled yt-dlp.

A version becomes known to work after a successful import or stream extraction.
Untried updates do not displace that working version from the rollback slot.
If the active runtime fails a version probe or extraction, geet tries the
previous verified runtime. If that succeeds, geet restores it and records the
failed version so the next check does not reinstall it. If both fail, geet keeps
the current version: private videos and network failures are not evidence of a
regression. A newer release can still be installed after rollback. A corrupt or
missing active executable also falls back to the verified previous copy.
There is no previous copy on the very first installation.

Old, unreferenced installations and interrupted staging directories are
removed at the next updater session. Current and previous installations stay
available. Existing saved audio and valid stream caches do not require setup.

## Checks

`zsh scripts/test.sh` covers offline verification, installation, persistence,
coalescing, throttling, corruption, rollback, and retry behavior. To exercise the
real official download, checksum, extraction, and version probe in a disposable
folder without Homebrew:

```sh
GEET_TEST_EXTRACTOR_UPDATE=1 swift test --disable-sandbox \
  --filter officialReleaseDownloadsAndRunsWithoutHomebrew
```

For YouTube extraction and native playback, run the opt-in checks described in
[playback startup](../scripts/testing/playback-startup.md).

## Failure messages

First-time setup failures distinguish connection loss, timeouts, downloads
that could not be verified, insufficient disk space, inability to save files,
and runtimes that cannot run on this Mac. They direct the listener to the
existing Check again action in Settings. The last failed check is preserved
across launches, including during the retry delay.

Background update failures appear in the YouTube playback section of Settings.
If a usable runtime is already installed, that message explicitly says playback
is ready. They do not open alerts or interrupt playback. Check again retries
both the update and the version probe; it does not hide a failed update behind
a successful probe of the old version.

YouTube errors use plain messages for private, unavailable, membership-only,
region-restricted, or sign-in-required videos, request limits, unreadable
responses, and refused audio streams. Audio-response failures keep their cause
even when the response body is cancelled to enforce the range size limit. Messages include a next step and never display executable paths,
provider diagnostics, or signed media URLs. Failed setup does not put individual
links into the extraction failure cooldown.
