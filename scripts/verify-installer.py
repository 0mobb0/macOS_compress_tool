#!/usr/bin/env python3
"""Inspect the installer and byte-compare its extracted app to the source bundle."""
import hashlib
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

package = Path(sys.argv[1]).resolve()
source = Path(sys.argv[2]).resolve()
with (source / 'Contents/Info.plist').open('rb') as f:
    info = plistlib.load(f)
with tempfile.TemporaryDirectory() as tmp:
    expanded = Path(tmp) / 'expanded'
    subprocess.run(['pkgutil', '--expand-full', str(package), str(expanded)], check=True)
    distribution = ET.parse(expanded / 'Distribution').getroot()
    assert distribution.find('product').get('version') == info['CFBundleShortVersionString']
    assert distribution.find('options').get('hostArchitectures') == 'arm64,x86_64'
    assert distribution.find('options').get('require-scripts') == 'false'
    assert distribution.find('domains').get('enable_currentUserHome') == 'false'
    assert distribution.find('domains').get('enable_localSystem') == 'true'
    assert distribution.find('domains').get('enable_anywhere') == 'false'
    assert distribution.find('volume-check/allowed-os-versions/os-version').get('min') == info['LSMinimumSystemVersion']
    assert distribution.find('pkg-ref/must-close/app').get('id') == info['CFBundleIdentifier']
    for name in ['welcome', 'readme', 'conclusion']:
        resource = distribution.find(name).get('file')
        assert (expanded / 'Resources' / resource).is_file(), resource
    assert not list(expanded.rglob('Scripts')), 'Unexpected installer scripts'
    components = list(expanded.glob('*.pkg'))
    assert len(components) == 1
    component = ET.parse(components[0] / 'PackageInfo').getroot()
    assert component.get('identifier') == 'io.github.0mobb0.cleanzip.pkg'
    assert component.get('install-location') == '/'
    assert not component.findall('relocate/*'), 'App must not relocate outside /Applications'
    assert component.get('relocatable') == 'false'
    for tag in ['upgrade-bundle', 'strict-identifier', 'bundle-version']:
        assert component.find(tag + '/bundle').get('id') == info['CFBundleIdentifier'], tag
    payload = components[0] / 'Payload'
    app = payload / 'Applications/CleanZip.app'
    assert {p.name for p in payload.iterdir()} == {'Applications'}
    assert {p.name for p in (payload / 'Applications').iterdir()} == {'CleanZip.app'}
    def files(root):
        return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in root.rglob('*') if p.is_file()}
    assert files(app) == files(source), 'Installer payload differs from the tested app'
    assert (app / 'Contents/MacOS/CleanZip').stat().st_mode & 0o111
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    subprocess.run(['lipo', str(app / 'Contents/MacOS/CleanZip'), '-verify_arch', 'arm64', 'x86_64'], check=True)
print('PASS: installer payload, signature integrity, architectures, destination, update policy, OS requirement and Chinese resources.')
