#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/outputs/Maja.app"

cd "$ROOT"
cargo build --release -p maja-core
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/work/clang-cache"
mkdir -p "$SWIFTPM_MODULECACHE_OVERRIDE"
"$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" build -c debug --scratch-path .build --disable-sandbox
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/debug/Maja" "$APP/Contents/MacOS/Maja"
ICON_PNG="$ROOT/work/MajaIcon.png"
ICONSET="$ROOT/work/Maja.iconset"
ICON_ICNS="$ROOT/work/Maja.icns"
mkdir -p "$ROOT/work"
mkdir -p "$ICONSET"
"$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" \
  -module-cache-path "$ROOT/work/clang-cache" \
  "$ROOT/scripts/make-app-icon.swift" "$ROOT/Sources/MajaApp/Resources/MajaIcon.svg" "$ICON_PNG"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$double" "$double" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
python3 "$ROOT/scripts/make-icns.py" "$ICONSET" "$ICON_ICNS"
cp "$ICON_ICNS" "$APP/Contents/Resources/Maja.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Maja</string>
<key>CFBundleDisplayName</key><string>Maja</string>
<key>CFBundleIdentifier</key><string>dev.maja.filemanager</string>
<key>CFBundleVersion</key><string>0.1.1</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleExecutable</key><string>Maja</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>Maja.icns</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$APP" || true
echo "Built $APP"
