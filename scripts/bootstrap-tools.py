#!/usr/bin/env python3
"""Install verified upstream helpers into ignored Tools/, never at app launch."""
import hashlib
import io
import json
import os
import platform
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "Tools"
HEADERS = {"User-Agent": "Geet-build/0.1", "Accept": "application/vnd.github+json"}

def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120) as response:
        return response.read()

def install(repo, asset_name, output_name, zipped=False):
    release = json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/latest"))
    asset = next(a for a in release["assets"] if a["name"] == asset_name)
    digest = asset.get("digest") or ""
    if not digest.startswith("sha256:"):
        raise RuntimeError(f"No SHA-256 digest published for {asset_name}; refusing unverified download")
    data = fetch(asset["browser_download_url"])
    if hashlib.sha256(data).hexdigest() != digest.removeprefix("sha256:"):
        raise RuntimeError(f"Checksum mismatch for {asset_name}")
    if zipped:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            data = archive.read("deno")
    target = DEST / output_name
    temporary = DEST / (output_name + ".new")
    temporary.write_bytes(data)
    temporary.chmod(0o755)
    os.replace(temporary, target)
    return {"repository": repo, "version": release["tag_name"], "asset": asset_name, "sha256": digest.removeprefix("sha256:")}

if __name__ == "__main__":
    DEST.mkdir(exist_ok=True)
    arch = "aarch64" if platform.machine() == "arm64" else "x86_64"
    versions = {
        "yt-dlp": install("yt-dlp/yt-dlp", "yt-dlp_macos", "yt-dlp"),
        "deno": install("denoland/deno", f"deno-{arch}-apple-darwin.zip", "deno", zipped=True),
    }
    (ROOT / "scripts" / "tools-lock.json").write_text(json.dumps(versions, indent=2) + "\n")
    print(json.dumps({key: value["version"] for key, value in versions.items()}))
