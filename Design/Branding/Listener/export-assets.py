#!/usr/bin/env python3
"""Export text-free geet assets from the selected Listener vector master.

Requires Python 3, librsvg (rsvg-convert), ImageMagick, and macOS iconutil.
Run from any directory. The generated SVGs contain filled paths, never fonts
or embedded raster images. Source artwork and trace are kept beside this file.
"""

from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
INK, IVORY, FOREST, AMBER = '#20211C', '#F4F0E7', '#355A48', '#C19A63'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


tree = ET.parse(ROOT / 'source/listener-traced.svg').getroot()
_, _, MW, MH = map(float, tree.attrib['viewBox'].split())
original = tree.find(f'{{{NS}}}g')
original.attrib.pop('fill', None)
PATHS = ET.tostring(original, encoding='unicode')


def mark(x, y, width, height, color):
    scale = min(width / MW, height / MH)
    tx = x + (width - MW * scale) / 2
    ty = y + (height - MH * scale) / 2
    return f'<g fill="{color}" transform="translate({tx:.6f} {ty:.6f}) scale({scale:.9f})">{PATHS}</g>'


def svg(width, height, body, title='geet Listener symbol'):
    return (f'<svg xmlns="{NS}" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}" role="img" aria-label="{title}">'
            f'<title>{title}</title>{body}</svg>\n')


def write(name, body):
    path = ROOT / 'svg' / f'{name}.svg'
    path.write_text(body)
    return path


def render(source, dest, size, fmt='png'):
    run('rsvg-convert', '--format', fmt, '--width', size, '--height', size,
        '--output', dest, source)


for directory in ('svg', 'png', 'pdf', 'macos/Geet.iconset'):
    (ROOT / directory).mkdir(parents=True, exist_ok=True)

variants = {'ink': INK, 'forest': FOREST, 'ivory': IVORY, 'black': '#000000', 'white': '#FFFFFF'}
for name, color in variants.items():
    source = write(f'geet-logo-{name}', svg(1024, 1024, mark(64, 64, 896, 896, color)))
    for size in (512, 1024, 2048):
        render(source, ROOT / 'png' / f'geet-logo-{name}-{size}.png', size)
    render(source, ROOT / 'pdf' / f'geet-logo-{name}.pdf', 1024, 'pdf')

# Tight, color-adaptive master for inline use, with no external dependencies.
write('geet-logo', svg(int(MW), int(MH), mark(0, 0, MW, MH, 'currentColor')))

# macOS icon tile: standard 80.5% tile footprint, transparent outer canvas.
# Background and portrait are vector shapes; only the ambient shadow uses a filter.
shadow = ('<defs><filter id="shadow" x="-20%" y="-20%" width="140%" height="145%" '
          'color-interpolation-filters="sRGB"><feDropShadow dx="0" dy="12" '
          'stdDeviation="15" flood-color="#111A14" flood-opacity="0.16"/></filter></defs>')
tile = f'<rect x="100" y="100" width="824" height="824" rx="184" fill="{IVORY}" filter="url(#shadow)"/>'
icon = write('geet-app-icon', svg(1024, 1024, shadow + tile + mark(202, 212, 620, 600, FOREST), 'geet app icon'))
render(icon, ROOT / 'png/geet-app-icon-1024.png', 1024)
render(icon, ROOT / 'png/geet-app-icon-2048.png', 2048)

# Full-bleed source for contexts that apply their own icon mask.
flat = write('geet-app-icon-unmasked', svg(1024, 1024,
    f'<rect width="1024" height="1024" fill="{IVORY}"/>' + mark(152, 162, 720, 700, FOREST), 'geet app icon, unmasked'))
render(flat, ROOT / 'png/geet-app-icon-unmasked-1024.png', 1024)

# A true alpha template: macOS supplies foreground color in light and dark modes.
template = write('geet-menu-bar-template', svg(18, 18, mark(0.5, 0.5, 17, 17, '#000000')))
for size, suffix in ((18, ''), (36, '@2x')):
    render(template, ROOT / 'macos' / f'geet-menu-bar-template{suffix}.png', size)
render(template, ROOT / 'macos/geet-menu-bar-template.pdf', 18, 'pdf')

iconset = ROOT / 'macos/Geet.iconset'
for size in (16, 32, 128, 256, 512):
    render(icon, iconset / f'icon_{size}x{size}.png', size)
    render(icon, iconset / f'icon_{size}x{size}@2x.png', size * 2)
run('iconutil', '-c', 'icns', iconset, '-o', ROOT / 'macos/Geet.icns')

# Keep the existing application build inputs in sync with the asset package.
shutil.copy2(ROOT / 'png/geet-app-icon-1024.png', REPO / 'Design/Assets/app-icon.png')
shutil.copy2(ROOT / 'macos/Geet.icns', REPO / 'Sources/Geet/Resources/Geet.icns')
shutil.copy2(ROOT / 'macos/geet-menu-bar-template.pdf', REPO / 'Sources/Geet/Resources/GeetMenuBar.pdf')
shutil.copy2(ROOT / 'typography/Newsreader.ttf', REPO / 'Sources/Geet/Resources/Newsreader.ttf')
shutil.copy2(ROOT / 'typography/OFL.txt', REPO / 'Sources/Geet/Resources/Newsreader-OFL.txt')

# Actual exported assets, reused at native dimensions for visual inspection.
preview_body = (
    f'<rect width="1440" height="840" fill="{IVORY}"/>'
    f'<rect x="720" width="720" height="840" fill="{FOREST}"/>'
    + mark(95, 65, 530, 520, INK)
    + mark(815, 65, 530, 520, IVORY)
    + '<svg x="80" y="600" width="180" height="180" viewBox="0 0 1024 1024">'
    + shadow + tile + mark(202, 212, 620, 600, FOREST) + '</svg>'
)
# Small icon samples are embedded as PNGs to show the real raster exports.
import base64
for x, size in ((315, 16), (375, 32), (465, 64), (575, 128)):
    sample = ROOT / 'macos/Geet.iconset' / f'icon_{size}x{size}.png'
    if size == 64:
        sample = ROOT / 'macos/Geet.iconset/icon_32x32@2x.png'
    data = base64.b64encode(sample.read_bytes()).decode()
    preview_body += f'<image x="{x}" y="{690-size/2}" width="{size}" height="{size}" href="data:image/png;base64,{data}"/>'
for x, bg, fg in ((850, IVORY, '#000000'), (1100, '#20211C', '#FFFFFF')):
    preview_body += f'<rect x="{x}" y="630" width="180" height="110" rx="14" fill="{bg}"/>'
    preview_body += mark(x + 45, 668, 18, 18, fg) + mark(x + 92, 666, 22, 22, fg)
preview = ROOT / 'preview.svg'
preview.write_text(svg(1440, 840, preview_body, 'geet Listener asset preview'))
run('rsvg-convert', '--output', ROOT / 'preview.png', preview)

manifest = {
    'brand': 'geet', 'direction': 'Listener', 'text_in_logo': False,
    'typography': json.loads((ROOT / 'typography/tokens.json').read_text()),
    'palette': {'ink': INK, 'ivory': IVORY, 'forest': FOREST, 'amber': AMBER},
    'source': 'Built-in ImageGen refinement of approved 04-listener.png; symbol only, traced to filled vector paths with Potrace 1.16.',
    'svg': 'Actual filled vector paths, with no fonts or embedded raster artwork.',
    'macos': {'canvas': 1024, 'tile': [100, 100, 824, 824], 'template_point_size': 18,
              'iconset_pixel_sizes': [16, 32, 64, 128, 256, 512, 1024]},
    'files': []
}
for path in sorted(ROOT.rglob('*')):
    if not path.is_file() or path.name == 'manifest.json':
        continue
    data = path.read_bytes()
    manifest['files'].append({'path': str(path.relative_to(ROOT)), 'bytes': len(data),
                              'sha256': hashlib.sha256(data).hexdigest()})
(ROOT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Exported {len(manifest["files"])} files to {ROOT}')
