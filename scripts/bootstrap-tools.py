#!/usr/bin/env python3
"""Install checksum-verified upstream helpers into ignored Tools/, never at launch."""
import argparse
import hashlib
import io
import json
import os
import platform
from pathlib import Path, PurePosixPath
import shutil
import stat
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "Tools"
HEADERS = {"User-Agent": "geet-build/0.1", "Accept": "application/vnd.github+json"}


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120) as response:
        return response.read()


def unpack(data, destination):
    """Keep the complete runtime and executable modes; reject escaping entries."""
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for item in archive.infolist():
            name = PurePosixPath(item.filename)
            mode = item.external_attr >> 16
            if name.is_absolute() or ".." in name.parts or "\\" in item.filename or stat.S_ISLNK(mode):
                raise RuntimeError(f"Unsafe archive entry: {item.filename}")
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise RuntimeError(f"Unsupported archive entry: {item.filename}")
            target = destination.joinpath(*name.parts)
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(item))
                target.chmod(0o755 if mode & 0o111 else 0o644)


def replace_tree(staged, target):
    # Bootstrap never edits a running app. Keep the previous Tools/ copy until
    # the verified replacement is complete, including migration from a file.
    backup = target.with_name(target.name + ".previous")
    if backup.exists():
        raise RuntimeError(f"Previous tool backup exists: {backup}")
    had_target = target.exists()
    if had_target:
        target.rename(backup)
    try:
        staged.rename(target)
    except BaseException:
        if had_target:
            backup.rename(target)
        raise
    if had_target:
        if backup.is_dir():
            shutil.rmtree(backup)
        else:
            backup.unlink()


def install(repo, asset_name, output_name, zipped=False, directory=False, locked=None):
    if locked:
        # The reviewed lock already records the published digest. Normal builds
        # need no API quota or credentials, including on shared CI runners.
        version = locked["version"]
        digest = locked["sha256"]
        url = f"https://github.com/{repo}/releases/download/{version}/{asset_name}"
    else:
        release = json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/latest"))
        asset = next(a for a in release["assets"] if a["name"] == asset_name)
        published = asset.get("digest") or ""
        if not published.startswith("sha256:"):
            raise RuntimeError(f"No SHA-256 digest published for {asset_name}; refusing unverified download")
        version, digest, url = release["tag_name"], published.removeprefix("sha256:"), asset["browser_download_url"]
    print(f"Downloading {asset_name} ({version})", flush=True)
    data = fetch(url)
    if hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError(f"Checksum mismatch for {asset_name}")
    with tempfile.TemporaryDirectory(prefix=".geet-tool-", dir=DEST) as staging:
        staged = Path(staging) / output_name
        if directory:
            staged.mkdir()
            unpack(data, staged)
            if not (staged / "yt-dlp_macos").is_file() or not (staged / "_internal").is_dir():
                raise RuntimeError("The unpacked yt-dlp runtime is incomplete")
        else:
            if zipped:
                with zipfile.ZipFile(io.BytesIO(data)) as archive:
                    data = archive.read("deno")
            staged.write_bytes(data)
            staged.chmod(0o755)
        replace_tree(staged, DEST / output_name)
    return {"repository": repo, "version": version, "asset": asset_name, "sha256": digest}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true", help="Update helpers and lock to upstream's latest releases")
    args = parser.parse_args()
    DEST.mkdir(exist_ok=True)
    lock_file = ROOT / "scripts" / "tools-lock.json"
    locked = {} if args.update else json.loads(lock_file.read_text())
    arch = "aarch64" if platform.machine() == "arm64" else "x86_64"
    deno_asset = f"deno-{arch}-apple-darwin.zip"
    if locked and (locked["yt-dlp"]["asset"] != "yt-dlp_macos.zip" or locked["deno"]["asset"] != deno_asset):
        raise RuntimeError("Locked helpers do not match this packaging or architecture; use --update")
    versions = {
        "yt-dlp": install("yt-dlp/yt-dlp", "yt-dlp_macos.zip", "yt-dlp", directory=True, locked=locked.get("yt-dlp")),
        "deno": install("denoland/deno", deno_asset, "deno", zipped=True, locked=locked.get("deno")),
    }
    temporary = lock_file.with_suffix(".json.new")
    temporary.write_text(json.dumps(versions, indent=2) + "\n")
    os.replace(temporary, lock_file)
    print(json.dumps({key: value["version"] for key, value in versions.items()}))


if __name__ == "__main__":
    main()
