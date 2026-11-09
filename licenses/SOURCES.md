# Corresponding source for bundled tools

These downloads are provided at no charge by the original projects. They are
the preferred source forms, including upstream build instructions. No helper
source was modified by geet; only Apple signatures were replaced. The pinned
binary archive names and SHA-256 checksums are in `scripts/tools-lock.json`.

## Downloaded yt-dlp runtime

yt-dlp is not bundled. geet downloads the official macOS archive directly from
upstream, verifies GitHub's published SHA-256 digest, and preserves its notices.
Find the active and previous versions in `Geet/ExtractorUpdates/state.json` in
Application Support. For each recorded `VERSION`, source and build instructions
are available at:

- `https://github.com/yt-dlp/yt-dlp/archive/refs/tags/VERSION.tar.gz`
- `https://github.com/yt-dlp/yt-dlp/blob/VERSION/bundle/requirements/macos.txt`
- `https://github.com/yt-dlp/yt-dlp/blob/VERSION/bundle/pyinstaller.py`

The runtime's `_internal/THIRD_PARTY_LICENSES.txt` preserves upstream dependency
notices. geet does not modify or re-sign downloaded runtimes.

## Deno 2.9.8

- [Complete Deno source archive](https://github.com/denoland/deno/archive/refs/tags/v2.9.8.tar.gz)
- [Build instructions](https://github.com/denoland/deno/blob/v2.9.8/.github/CONTRIBUTING.md)
- [Pinned Rust dependencies](https://github.com/denoland/deno/blob/v2.9.8/Cargo.lock)
- [V8 integration and build instructions](https://github.com/denoland/rusty_v8)
- [Exact V8 integration source and submodule pins](https://github.com/denoland/rusty_v8/tree/v150.4.0)

License notices from the exact upstream Cargo.lock's checksum-verified source
crates, with direct source download URLs, are included in
`deno-THIRD_PARTY_LICENSES.txt`. geet's own matching source is attached to each
release as `geet-source.tar.gz` and is also available through the release tag.

`v8-THIRD_PARTY_LICENSES.txt` preserves the license texts for the V8 integration
and its pinned C/C++ submodules, together with each exact source revision.
