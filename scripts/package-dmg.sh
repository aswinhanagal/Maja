#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/outputs/Maja.app"
STAGING="$ROOT/work/dmg-root"
DMG="$ROOT/outputs/Maja-0.1.1.dmg"

if [[ ! -d "$APP" ]]; then
  echo "Missing $APP. Build Maja before packaging." >&2
  exit 1
fi

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Maja.app"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/LICENSE" "$STAGING/LICENSE"
cat > "$STAGING/Install Maja.txt" <<'EOF'
Maja 0.1.1

Drag Maja.app to the Applications folder to install it.

Maja is licensed under the GNU General Public License, version 2 or later.
See the LICENSE file for the full license text.
EOF

hdiutil create \
  -volname "Maja 0.1.1" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

echo "Created $DMG"
