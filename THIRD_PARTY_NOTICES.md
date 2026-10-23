# Third-party software and assets

geet's own code is MIT licensed. Separately distributed helpers, fonts, and
assets retain their original licenses. The MIT license does not replace them.

- yt-dlp 2026.08.19: [source and build scripts](https://github.com/yt-dlp/yt-dlp/tree/2026.08.19), Unlicense for its own code. The bundled executable includes GPLv3+ components and is distributed under GPLv3+. Its complete upstream third-party notices are preserved in `Contents/Resources/Tools/yt-dlp/_internal/THIRD_PARTY_LICENSES.txt` and `licenses/yt-dlp-THIRD_PARTY_LICENSES.txt`. geet invokes this separate executable through its command-line interface. The upstream runtime is unchanged except for Apple code signatures.
- Deno 2.9.8: [source and build instructions](https://github.com/denoland/deno/tree/v2.9.8), MIT. Its license and dependency notices collected from checksum-verified source crates in its exact Cargo.lock are in `licenses/`.
- Newsreader: SIL Open Font License 1.1, included alongside the fonts in `Sources/Geet/Resources/Newsreader-OFL.txt`, the design directories, and `website/assets/OFL.txt`.
- Phosphor's Apple symbol in the website: MIT, `website/assets/phosphor-LICENSE`.
- The Listener and design-reference artwork were generated for this project. Playlist covers and screenshots may depict third-party artwork; no ownership of that artwork is claimed. YouTube content and artwork are not covered by geet's MIT license.

`licenses/SOURCES.md` identifies the corresponding source locations for bundled
helpers and their copyleft components. Every release includes these notices and
source directions beside the installer and inside the app. Tool updates must
refresh these files and verify the source links before publishing.
