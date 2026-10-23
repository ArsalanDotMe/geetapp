# Corresponding source for bundled tools

These downloads are provided at no charge by the original projects. They are
the preferred source forms, including upstream build instructions. No helper
source was modified by geet; only Apple signatures were replaced. The pinned
binary archive names and SHA-256 checksums are in `scripts/tools-lock.json`.

## yt-dlp 2026.08.19

- [Complete source archive](https://github.com/yt-dlp/yt-dlp/archive/refs/tags/2026.08.19.tar.gz)
- [Exact macOS build requirements](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/bundle/requirements/macos.txt)
- [Executable build script](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/bundle/pyinstaller.py)
- [Release workflow](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/.github/workflows/build.yml)
- [mutagen 1.48.1 source, GPL-2.0-or-later](https://pypi.org/project/mutagen/1.48.1/#files)
- [PyInstaller 6.22.0 source and bootloader, GPL with bootloader exception](https://pypi.org/project/pyinstaller/6.22.0/#files)
- [certifi 2026.7.22 source and certificate data, MPL-2.0](https://pypi.org/project/certifi/2026.7.22/#files)

The macOS helper uses Apple's system libedit, not GNU Readline. The upstream
aggregate license text also describes components for other platforms that are
not present in this macOS archive. The complete dependency pins above identify
the remaining permissively licensed Python modules and build tools.

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
