# Third-party software and assets

geet's own code is MIT licensed. Separately distributed helpers, fonts, and
assets retain their original licenses. The MIT license does not replace them.

- yt-dlp is downloaded directly from [official upstream releases](https://github.com/yt-dlp/yt-dlp/releases) after launch and is not included in the installer. Its own code is Unlicense; its macOS runtime includes GPLv3+ components and is distributed under GPLv3+. Each downloaded runtime preserves its upstream `_internal/THIRD_PARTY_LICENSES.txt`. The installed version and archive checksum are recorded in Application Support under `Geet/ExtractorUpdates/state.json`; corresponding source and build instructions are available at `https://github.com/yt-dlp/yt-dlp/tree/VERSION`, replacing `VERSION` with the recorded version. geet invokes the unchanged upstream runtime as a separate executable.
- Deno 2.9.8: [source and build instructions](https://github.com/denoland/deno/tree/v2.9.8), MIT. Its license and dependency notices collected from checksum-verified source crates in its exact Cargo.lock are in `licenses/`.
- Newsreader: SIL Open Font License 1.1, included alongside the fonts in `Sources/Geet/Resources/Newsreader-OFL.txt` and `website/assets/OFL.txt`.
- Phosphor's Apple symbol in the website: MIT, `website/assets/phosphor-LICENSE`.
- The Listener and design-reference artwork were generated for this project. Playlist covers and screenshots may depict third-party artwork; no ownership of that artwork is claimed. YouTube content and artwork are not covered by geet's MIT license.

`licenses/SOURCES.md` identifies the corresponding source locations for bundled
helpers and their copyleft components. Every release includes these notices and
source directions beside the installer and inside the app. Tool updates must
refresh these files and verify the source links before publishing.
