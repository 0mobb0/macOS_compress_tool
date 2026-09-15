#!/bin/bash
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
for arch in arm64 x86_64; do
    swift build -c release --product CleanZip --arch "$arch" --scratch-path ".build/release-$arch" --disable-sandbox --cache-path "$PWD/.build/cache"
done
app="$PWD/dist/CleanZip.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create .build/release-arm64/arm64-apple-macosx/release/CleanZip .build/release-x86_64/x86_64-apple-macosx/release/CleanZip -output "$app/Contents/MacOS/CleanZip"
swift scripts/icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CleanZip</string>
<key>CFBundleIdentifier</key><string>io.github.0mobb0.cleanzip</string>
<key>CFBundleName</key><string>CleanZip</string>
<key>CFBundleDisplayName</key><string>CleanZip · 清简压缩</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>© 2026 0mobb0. MIT License.</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Files and folders</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>public.item</string><string>public.folder</string></array>
</dict></array>
</dict></plist>
PLIST
cp LICENSE "$app/Contents/Resources/LICENSE"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict "$app"
# This ZIP distributes the app bundle; user archives use ZipCore.
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$app" dist/CleanZip-1.0.1-universal.zip
(cd dist && shasum -a 256 CleanZip-1.0.1-universal.zip > SHA256SUMS.txt)
printf 'Built: %s\n' "$app"
