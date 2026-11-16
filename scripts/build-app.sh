#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
app="$PWD/.build/Spine.app"
iconset="$PWD/.build/AppIcon.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
cp "$bin_path/Spine" "$app/Contents/MacOS/Spine"
ditto "$bin_path/Spine_Spine.bundle" "$app/Contents/Resources/Spine_Spine.bundle"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Sources/Spine/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Sources/Spine/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>Spine</string>
    <key>CFBundleIdentifier</key><string>com.naveenv92.Spine</string>
    <key>CFBundleName</key><string>Spine</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

plutil -lint "$app/Contents/Info.plist"
test -x "$app/Contents/MacOS/Spine"
test -f "$app/Contents/Resources/Spine_Spine.bundle/Contents/Resources/AppIcon.png"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
printf '\nBuilt %s\n' "$app"
