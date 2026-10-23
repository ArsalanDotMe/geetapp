#!/usr/bin/env python3
"""Build, notarize, verify, and publish an Apple silicon release from a clean commit."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
REPO = "ArsalanDotMe/geetapp"
MACHO = {bytes.fromhex(x) for x in ("cffaedfe", "cefaedfe", "cafebabe", "bebafeca", "cafebabf")}


def run(*args, capture=False, **kwargs):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None, **kwargs)
    return result.stdout.strip() if capture else None


def clean_commit():
    if run("git", "status", "--porcelain", capture=True):
        raise RuntimeError("Commit all source changes before building or publishing a release")
    return run("git", "rev-parse", "HEAD", capture=True)


def macho_files(app):
    for path in sorted(app.rglob("*")):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                if stream.read(4) in MACHO:
                    yield path


def normalize_frameworks(app):
    # The upstream ZIP materializes framework symlinks as duplicate files.
    # Restore Apple's versioned layout before signing, preserving all bytes.
    for framework in app.rglob("*.framework"):
        versions = framework / "Versions"
        if not versions.is_dir():
            continue
        actual = [p for p in versions.iterdir() if p.name != "Current" and p.is_dir()]
        if len(actual) != 1:
            raise RuntimeError(f"Expected one framework version: {framework}")
        version = actual[0]
        for duplicate, canonical, target in [
            (versions / "Current", version, version.name),
            (framework / framework.stem, version / framework.stem, "Versions/Current/" + framework.stem),
            (framework / "Resources", version / "Resources", "Versions/Current/Resources"),
        ]:
            if duplicate.is_symlink():
                if duplicate.resolve() != canonical.resolve():
                    raise RuntimeError(f"Unexpected framework link: {duplicate}")
                continue
            if duplicate.is_dir():
                contents = sorted(p.relative_to(duplicate) for p in duplicate.rglob("*") if p.is_file())
                expected = sorted(p.relative_to(canonical) for p in canonical.rglob("*") if p.is_file())
                if contents != expected or any((duplicate / p).read_bytes() != (canonical / p).read_bytes() for p in contents):
                    raise RuntimeError(f"Framework copies differ: {duplicate}")
                shutil.rmtree(duplicate)
            elif duplicate.is_file():
                if duplicate.read_bytes() != canonical.read_bytes():
                    raise RuntimeError(f"Framework copies differ: {duplicate}")
                duplicate.unlink()
            duplicate.symlink_to(target)


def verify_app(app, signed):
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleDisplayName"] == "geet"
    assert info["LSMinimumSystemVersion"] == "26.0"
    assert run("lipo", "-archs", app / "Contents/MacOS/Geet", capture=True) == "arm64"
    for path in macho_files(app):
        assert "arm64" in run("lipo", "-archs", path, capture=True).split(), path
        links = run("otool", "-L", path, capture=True)
        assert "/opt/homebrew/" not in links and "/usr/local/" not in links, path
        if signed:
            run("codesign", "--verify", "--strict", path)
    resources = app / "Contents/Resources"
    assert json.loads((ROOT / "licenses/tools-lock.json").read_text()) == json.loads((ROOT / "scripts/tools-lock.json").read_text()), "Refresh dependency notices and their lock before releasing"
    assert (resources / "Tools/yt-dlp/_internal/THIRD_PARTY_LICENSES.txt").read_bytes() == (resources / "Licenses/yt-dlp-THIRD_PARTY_LICENSES.txt").read_bytes(), "yt-dlp notices do not match the packaged runtime"
    for name in ("LICENSE", "THIRD_PARTY_NOTICES.md", "SOURCES.md", "deno-LICENSE.txt",
                 "deno-THIRD_PARTY_LICENSES.txt", "yt-dlp-LICENSE.txt", "yt-dlp-THIRD_PARTY_LICENSES.txt"):
        assert (resources / "Licenses" / name).stat().st_size > 0, name
    assert (resources / "Licenses/v8-THIRD_PARTY_LICENSES.txt").stat().st_size > 0
    env = dict(os.environ, PATH="/usr/bin:/bin", PYTHONHOME="", PYTHONPATH="")
    lock = json.loads((ROOT / "scripts/tools-lock.json").read_text())
    assert run(resources / "Tools/yt-dlp/yt-dlp_macos", "--ignore-config", "--version", capture=True, env=env) == lock["yt-dlp"]["version"]
    assert run(resources / "Tools/deno", "--version", capture=True, env=env).splitlines()[0].split()[:2] == ["deno", lock["deno"]["version"].lstrip("v")]
    run(resources / "Tools/deno", "eval", "let n = 0; for (let i = 0; i < 100000; i++) n += i; if (n !== 4999950000) throw Error('JIT check failed');", env=env)
    run(app / "Contents/MacOS/Geet", "--validate-discover-feed", ROOT / "Sources/GeetCore/Resources/discover-v1.json")
    if signed:
        run("xcrun", "stapler", "validate", app)
        run("spctl", "--assess", "--type", "execute", "--verbose=2", app)


def verify_dmg(dmg, signed=True):
    run("hdiutil", "verify", dmg)
    if signed:
        run("codesign", "--verify", "--verbose=2", dmg)
        run("xcrun", "stapler", "validate", dmg)
        run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", dmg)
    with tempfile.TemporaryDirectory(prefix="geet-mount-") as mount:
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
        try:
            assert (Path(mount) / "Applications").is_symlink()
            verify_app(Path(mount) / "Geet.app", signed)
        finally:
            run("hdiutil", "detach", mount)


def build(args):
    if platform.machine() != "arm64":
        raise RuntimeError("Build on an Apple silicon Mac")
    commit = clean_commit()
    output = ROOT / "build/releases" / args.version
    if output.exists():
        raise RuntimeError(f"Release staging already exists: {output}")
    identity = os.environ.get("GEET_SIGNING_IDENTITY", "Developer ID Application: Mashal Tech OU (34T9L3FGZC)")
    profile = os.environ.get("GEET_NOTARY_PROFILE", "geet-notary")
    if not args.unsigned:
        identities = run("security", "find-identity", "-v", "-p", "codesigning", capture=True)
        assert identity in identities, "Developer ID signing identity is unavailable"
        run("xcrun", "notarytool", "history", "--keychain-profile", profile, capture=True)
    run("python3", "scripts/bootstrap-tools.py")
    assert clean_commit() == commit, "Bootstrap changed the dependency lock"
    run("zsh", "scripts/test.sh")
    output.mkdir(parents=True)
    app = output / "Geet.app"
    env = dict(os.environ, GEET_BUILD_DESTINATION=str(app), GEET_VERSION=args.version,
               GEET_BUILD_NUMBER=run("git", "rev-list", "--count", "HEAD", capture=True))
    run("zsh", "scripts/build.sh", "release", env=env)
    normalize_frameworks(app)
    if args.unsigned:
        run("codesign", "--force", "--deep", "--sign", "-", app)
    if not args.unsigned:
        for path in macho_files(app):
            command = ["codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity]
            # V8 requires JIT; keep this entitlement confined to Deno.
            if path == app / "Contents/Resources/Tools/deno":
                command += ["--entitlements", str(ROOT / "scripts/deno-entitlements.plist")]
            run(*command, path)
        for framework in sorted(app.rglob("*.framework"), key=lambda p: len(p.parts), reverse=True):
            run("codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity, framework)
        run("codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity, app)
        archive = output / "notarization.zip"
        run("ditto", "-c", "-k", "--keepParent", app, archive)
        run("xcrun", "notarytool", "submit", archive, "--keychain-profile", profile, "--wait")
        run("xcrun", "stapler", "staple", app)
        archive.unlink()
    verify_app(app, not args.unsigned)
    stage = output / "image"
    stage.mkdir()
    run("ditto", app, stage / "Geet.app")
    (stage / "Applications").symlink_to("/Applications")
    shutil.copytree(app / "Contents/Resources/Licenses", stage / "Licenses")
    (stage / "Install.txt").write_text("Drag geet to Applications, then open it. Click the Listener icon in your menu bar.\nRequires an Apple silicon Mac with macOS 26 or later.\n")
    dmg = output / "geet-apple-silicon.dmg"
    run("hdiutil", "create", "-volname", "geet", "-srcfolder", stage, "-format", "UDZO", "-ov", dmg)
    if not args.unsigned:
        run("codesign", "--timestamp", "--sign", identity, dmg)
        run("xcrun", "notarytool", "submit", dmg, "--keychain-profile", profile, "--wait")
        run("xcrun", "stapler", "staple", dmg)
    verify_dmg(dmg, not args.unsigned)
    run("git", "archive", "--format=tar.gz", f"--prefix=geet-{args.version}/", "-o", output / "geet-source.tar.gz", commit)
    shutil.copy(ROOT / "licenses/SOURCES.md", output / "SOURCES.md")
    shutil.copy(ROOT / "THIRD_PARTY_NOTICES.md", output / "THIRD_PARTY_NOTICES.md")
    files = [dmg, output / "geet-source.tar.gz", output / "SOURCES.md", output / "THIRD_PARTY_NOTICES.md"]
    assert clean_commit() == commit, "Source changed while building; do not publish this artifact"
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (output / "SHA256SUMS").write_text("".join(f"{digest}  {name}\n" for name, digest in hashes.items()))
    (output / "release.json").write_text(json.dumps(dict(version=args.version, commit=commit, signed=not args.unsigned, sha256=hashes), indent=2) + "\n")
    print(f"Verified release: {output}")


def publish(args):
    commit = clean_commit()
    output = ROOT / "build/releases" / args.version
    manifest = json.loads((output / "release.json").read_text())
    assert manifest["version"] == args.version and manifest["commit"] == commit and manifest["signed"]
    for name, digest in manifest["sha256"].items():
        assert hashlib.sha256((output / name).read_bytes()).hexdigest() == digest, name
    assert run("gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner", capture=True) == REPO
    live = run("git", "ls-remote", "origin", "refs/heads/main", capture=True).split()[0]
    assert live == commit, "Push the release commit to main first"
    tag = "v" + args.version
    existing = run("git", "ls-remote", "origin", "refs/tags/" + tag, capture=True)
    assert not existing or existing.split()[0] == commit, "The remote tag points to another commit"
    verify_dmg(output / "geet-apple-silicon.dmg")
    notes = output / "release-notes.md"
    notes.write_text(f"geet {args.version} for Apple silicon Macs running macOS 26 or later.\n\nDownload **geet-apple-silicon.dmg**, open it, and drag geet to Applications. The app and DMG are Developer ID signed, notarized by Apple, and stapled.\n\nStreaming and Discover are available without an account. Offline checkout is not available in this release.\n\nChecksums are in SHA256SUMS. geet's source is MIT licensed; bundled tools retain their own licenses. See the attached THIRD_PARTY_NOTICES.md and SOURCES.md for their licenses and corresponding source downloads.\n\nSource commit: {commit}\n")
    # A draft keeps the installer hidden until every asset has uploaded.
    run("gh", "release", "create", tag, "--repo", REPO, "--target", commit, "--draft", "--title", "geet " + args.version, "--notes-file", notes,
        *[output / name for name in manifest["sha256"]], output / "SHA256SUMS", output / "release.json")
    run("gh", "release", "edit", tag, "--repo", REPO, "--draft=false", "--latest")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "publish", "verify"])
    parser.add_argument("version")
    parser.add_argument("--unsigned", action="store_true", help="CI validation only; cannot publish")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("Version must have the form 1.2.3")
    if args.command == "build":
        build(args)
    elif args.command == "publish":
        publish(args)
    else:
        verify_dmg(ROOT / "build/releases" / args.version / "geet-apple-silicon.dmg", not args.unsigned)
