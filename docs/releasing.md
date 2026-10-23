# Releasing geet

Public downloads are built on an Apple silicon Mac with macOS 26+, Xcode 26+
and Swift 6.2+. Python 3 and an authenticated GitHub CLI are required. The
release version is supplied explicitly; app metadata is stamped during staging.

## Prerequisites

Use a Developer ID Application identity with its private key in the login
keychain. Store notarization credentials with `xcrun notarytool
store-credentials geet-notary`, following Apple's interactive prompts. Never put
credentials, certificates, or private keys in this repository or command history.
`GEET_SIGNING_IDENTITY` and `GEET_NOTARY_PROFILE` select existing local credentials.

Review tool versions in `scripts/tools-lock.json` and refresh `licenses/` and
its source directions when changing them. `python3 scripts/collect-deno-licenses.py`
collects Deno dependency notices from checksum-verified source crates in its
pinned lock. Preserve yt-dlp's bundled notices too. Update
`licenses/tools-lock.json` from `scripts/tools-lock.json` only after refreshing
and checking the notices and source links. Release verification rejects stale
license inventory pins and a yt-dlp notice that differs from the packaged copy.

## Build and publish

Start from a clean commit on `main`, push it, and wait for the Verify Apple
silicon release workflow to pass. Then run:

```sh
python3 scripts/release.py build 0.1.0
python3 scripts/release.py verify 0.1.0
python3 scripts/release.py publish 0.1.0
```

Replace `0.1.0` with the new semantic version. Build refuses an existing staging
directory rather than replacing a previous artifact. If a build fails, retain
its logs and move the staging directory aside before retrying.

Build downloads the checksum-pinned helpers, runs all unit tests, packages a
fresh release app, verifies Apple silicon support and absence of Homebrew
linkage, and signs nested Mach-O files before signing the app. Only Deno gets
the JIT entitlement. It notarizes and staples both app and DMG, mounts the DMG
read-only, and repeats verification on the actual packaged app with a minimal
PATH. Both the app and disk image must pass Gatekeeper. The DMG includes an
Applications shortcut and license notices.

The build also creates a source archive from the exact commit, SHA-256 checksums,
source directions, and a manifest recording the commit and signing state.
Publishing checks that the tree remains clean, all hashes still match, and
`HEAD` equals live `origin/main`. It rejects unsigned builds and conflicting
tags, verifies the DMG again, uploads all assets into a draft, and only then
publishes it as latest. If upload fails, inspect the draft with `gh release
view vVERSION` and finish or delete that draft deliberately before retrying.

The GitHub Actions workflow runs tests, the history scan, website checks, and an
unsigned build/mount/helper check on an Apple silicon macOS runner. Its DMG is
explicitly an unsigned CI artifact and cannot be published by the release
script. Signing credentials stay in the maintainer's keychain. Actions do not
receive private keys.

## Website

Both Download buttons use the stable latest-release asset address:

`https://github.com/ArsalanDotMe/geetapp/releases/latest/download/geet-apple-silicon.dmg`

Keep that asset name across releases. Verify the public download before
deploying the site. The website README documents deployment and the Discover
route. Check both the homepage and `/discover/v1.json` after each deployment.
