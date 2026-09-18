#!/bin/bash
# Actual installation tests only run on a disposable GitHub Actions macOS runner.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
if [ "${GITHUB_ACTIONS:-}" != true ]; then
    printf 'This integration test requires a disposable GitHub Actions runner.\n' >&2
    exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/CleanZip.app/Contents/Info.plist)
package="$PWD/dist/CleanZip-$version-installer.pkg"
app=/Applications/CleanZip.app
if [ -e "$app" ]; then
    printf 'Fresh-install test requires CleanZip to be absent.\n' >&2
    exit 1
fi
sudo /usr/sbin/installer -pkg "$package" -target /
python3 - "$app" <<'PY'
import hashlib,plistlib,sys
from pathlib import Path
app=Path(sys.argv[1]); source=Path('dist/CleanZip.app')
for path in source.rglob('*'):
    if path.is_file():
        assert (app/path.relative_to(source)).read_bytes()==path.read_bytes()
PY
codesign --verify --deep --strict "$app"
pkgutil --pkg-info io.github.0mobb0.cleanzip.pkg
# Reinstall must replace the bundle and remove obsolete files.
sudo touch "$app/Contents/Resources/obsolete-test-marker"
sudo /usr/sbin/installer -pkg "$package" -target /
test ! -e "$app/Contents/Resources/obsolete-test-marker"
codesign --verify --deep --strict "$app"
# A moved old copy must not redirect installation away from /Applications.
moved=$(mktemp -d "$RUNNER_TEMP/cleanzip-moved.XXXXXX")
sudo mv "$app" "$moved/CleanZip.app"
sudo /usr/sbin/installer -pkg "$package" -target /
test -d "$moved/CleanZip.app"
codesign --verify --deep --strict "$app"
# An older installer must leave a newer on-disk app alone.
sudo /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 999' "$app/Contents/Info.plist"
sudo /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 99.0.0' "$app/Contents/Info.plist"
sudo /usr/sbin/installer -pkg "$package" -target /
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = 999
printf 'PASS: fresh install, reinstall cleanup, fixed destination and newer-version protection.\n'
