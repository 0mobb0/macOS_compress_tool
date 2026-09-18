#!/bin/bash
# Build a standard macOS Installer package from the already-built app.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
app="${1:-$PWD/dist/CleanZip.app}"
if [ ! -d "$app" ]; then
    printf 'App not found: %s. Run scripts/build-app.sh first.\n' "$app" >&2
    exit 1
fi
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/CleanZip" -verify_arch arm64 x86_64
mkdir -p .build dist
stage=$(mktemp -d "$PWD/.build/installer.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/root/Applications"
ditto --noextattr --norsrc "$app" "$stage/root/Applications/CleanZip.app"
pkgbuild --analyze --root "$stage/root" "$stage/components.plist"
version=$(python3 - "$stage" <<'PY'
import plistlib,re,sys
from pathlib import Path
stage=Path(sys.argv[1])
with (stage/'root/Applications/CleanZip.app/Contents/Info.plist').open('rb') as f:
    info=plistlib.load(f)
assert info['CFBundleIdentifier']=='io.github.0mobb0.cleanzip'
version=info['CFBundleShortVersionString']; minimum=info['LSMinimumSystemVersion']
assert re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}',version)
assert re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}',minimum)
with (stage/'components.plist').open('rb') as f:
    components=plistlib.load(f)
assert len(components)==1 and components[0]['RootRelativeBundlePath']=='Applications/CleanZip.app'
components[0].update(BundleIsRelocatable=False,BundleIsVersionChecked=True,
                     BundleHasStrictIdentifier=True,BundleOverwriteAction='upgrade')
with (stage/'components.plist').open('wb') as f:
    plistlib.dump(components,f)
xml=Path('installer/Distribution.xml.in').read_text().replace('@VERSION@',version).replace('@MIN_OS@',minimum)
(stage/'Distribution.xml').write_text(xml)
print(version)
PY
)
pkgbuild --root "$stage/root" --component-plist "$stage/components.plist" \
    --identifier io.github.0mobb0.cleanzip.pkg --version "$version" \
    --install-location / --ownership recommended "$stage/CleanZip-component.pkg"
productbuild --distribution "$stage/Distribution.xml" --resources installer/resources \
    --package-path "$stage" "$stage/CleanZip-$version-installer.pkg"
python3 scripts/verify-installer.py "$stage/CleanZip-$version-installer.pkg" "$app"
mv "$stage/CleanZip-$version-installer.pkg" "dist/CleanZip-$version-installer.pkg"
(
    cd dist
    artifacts=("CleanZip-$version-installer.pkg")
    if [ -f "CleanZip-$version-universal.zip" ]; then artifacts+=("CleanZip-$version-universal.zip"); fi
    shasum -a 256 "${artifacts[@]}" > SHA256SUMS.txt
)
printf 'Built: %s/dist/CleanZip-%s-installer.pkg\n' "$PWD" "$version"
