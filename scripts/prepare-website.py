#!/usr/bin/env python3
"""Stage only public site files; never ship review evidence or deployment source."""
from pathlib import Path
import shutil
from html.parser import HTMLParser

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / 'website'
DOWNLOAD = 'https://github.com/ArsalanDotMe/geetapp/releases/latest/download/geet-apple-silicon.dmg'
REPOSITORY = 'https://github.com/ArsalanDotMe/geetapp'

class Check(HTMLParser):
    downloads = 0
    github = 0

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == 'a' and 'button' in values.get('class', '').split():
            assert values.get('href') == DOWNLOAD, 'Download button must use the stable release URL'
            self.downloads += 1
        if tag == 'a' and values.get('href', '').startswith('https://github.com/'):
            assert values['href'] in (REPOSITORY, DOWNLOAD, REPOSITORY + '/releases/latest')
            self.github += values['href'] == REPOSITORY
        for attr in ('href', 'src', 'srcset'):
            value = values.get(attr, '')
            if value.startswith('assets/'):
                assert (SITE / value).is_file(), value

check = Check()
check.feed((SITE / 'index.html').read_text())
assert check.downloads == 2 and check.github == 2
assert 'Public download coming soon' not in (SITE / 'index.html').read_text()
destination = SITE / 'dist'
if destination.exists():
    shutil.rmtree(destination)
destination.mkdir()
for name in ('index.html', 'styles.css', '_headers'):
    shutil.copy(SITE / name, destination / name)
shutil.copytree(SITE / 'assets', destination / 'assets')
print(f'Website ready: {destination}')
