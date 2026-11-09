# Developing geet

Requires an Apple silicon Mac with macOS 26+, Xcode 26 or newer with Swift 6.2+, and Python 3.

```sh
python3 scripts/bootstrap-tools.py
zsh scripts/build.sh
open build/Geet.app
```

The build bundles checksum-pinned Deno. On launch, geet downloads and verifies the latest stable yt-dlp runtime into Application Support, then checks daily for updates. A fresh installation needs GitHub access before YouTube playback works. Homebrew and a separate Python installation aren't needed. See [extractor updates](extractor-updates.md) for verification and rollback behavior.

Run the unit tests with:

```sh
zsh scripts/test.sh
```

See [playback startup checks](../scripts/testing/playback-startup.md) for optional native playback measurements, and [the release process](releasing.md) for signed, notarized Apple silicon DMGs.

Discover content is maintained separately; see [Discover publishing](../Discover/README.md).
