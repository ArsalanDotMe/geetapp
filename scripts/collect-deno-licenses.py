#!/usr/bin/env python3
"""Collect notices from checksum-verified source crates in the pinned Deno lock."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
from pathlib import Path
import re
import tarfile
import time
import tomllib
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
VERSION = 'v2.9.8'
CACHE = ROOT / 'build/license-cache'
CACHE.mkdir(parents=True, exist_ok=True)

def fetch(url):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=90) as response:
                return response.read()
        except Exception:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)

lock = fetch(f'https://raw.githubusercontent.com/denoland/deno/{VERSION}/Cargo.lock')
packages = [p for p in tomllib.loads(lock.decode())['package'] if p.get('source', '').startswith('registry+')]

def collect(package):
    name, version = package['name'], package['version']
    url = f'https://static.crates.io/crates/{name}/{name}-{version}.crate'
    cached = CACHE / f'{name}-{version}.crate'
    data = cached.read_bytes() if cached.exists() else fetch(url)
    if hashlib.sha256(data).hexdigest() != package['checksum']:
        raise RuntimeError(f'Source checksum mismatch: {name} {version}')
    cached.write_bytes(data)
    texts = []
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        for member in archive.getmembers():
            if member.isfile() and re.match(r'^(?:licen[cs]e|copying|notice|copyright)(?:[._-]|$)', Path(member.name).name, re.I):
                if member.size <= 2_000_000:
                    texts.append(f'\n--- {member.name} ---\n' + archive.extractfile(member).read().decode('utf-8', 'replace'))
        manifest = next(m for m in archive.getmembers() if m.name == f'{name}-{version}/Cargo.toml')
        metadata = tomllib.loads(archive.extractfile(manifest).read().decode())['package']
    return f'\n{"=" * 72}\n{name} {version}\nLicense expression: {metadata.get("license", "See included source license files")}\nSource: {url}\nSHA-256: {package["checksum"]}\n' + ''.join(texts)

with ThreadPoolExecutor(max_workers=16) as pool:
    notices = []
    for index, notice in enumerate(pool.map(collect, packages), 1):
        notices.append(notice)
        if index % 100 == 0:
            print(f'Collected {index}/{len(packages)} source crates', flush=True)
header = f'''Deno {VERSION}: dependency notices

Generated from the upstream Cargo.lock (SHA-256 {hashlib.sha256(lock).hexdigest()}).
All registry packages in that lock are included, including build tools and
platform-specific packages that may not be linked into the macOS executable.
Each source archive was verified against its Cargo.lock checksum. Source
download URLs and available license/notice texts follow. Deno's own MIT license
is in deno-LICENSE.txt. V8 and its dependencies retain their upstream licenses:
https://github.com/denoland/rusty_v8/tree/v150.4.0

'''
(ROOT / 'licenses/deno-THIRD_PARTY_LICENSES.txt').write_text(header + ''.join(notices))
print(f'Wrote notices for {len(packages)} checksum-verified crates', flush=True)
