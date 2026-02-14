#!/bin/bash
set -euo pipefail

# MediaFlow.app Bundle Builder
# Assembles a standalone .app bundle from the Swift frontend + PyInstaller-frozen backend

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/MediaFlow.app"
CONTENTS="$APP_DIR/Contents"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend/MediaFlow"

echo "=== MediaFlow App Bundle Builder ==="
echo ""

# Clean previous build
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# ─── Step 1: Build Swift frontend ───────────────────────────────────────────
echo "[1/5] Building Swift frontend (release)..."
cd "$FRONTEND_DIR"
swift build -c release 2>&1 | tail -5
SWIFT_BIN=$(swift build -c release --show-bin-path)/MediaFlow
if [ ! -f "$SWIFT_BIN" ]; then
    echo "ERROR: Swift binary not found at $SWIFT_BIN"
    exit 1
fi
echo "  ✓ Swift binary: $SWIFT_BIN"

# ─── Step 2: Freeze Python backend with PyInstaller ────────────────────────
echo "[2/5] Freezing Python backend with PyInstaller..."
cd "$BACKEND_DIR"

# Ensure PyInstaller is available
if ! python3 -c "import PyInstaller" 2>/dev/null; then
    echo "  Installing PyInstaller..."
    pip3 install pyinstaller --quiet
fi

# Clean previous PyInstaller output
rm -rf dist build

pyinstaller mediaflow-server.spec --noconfirm 2>&1 | tail -5

if [ ! -f "dist/backend/mediaflow-server" ]; then
    echo "ERROR: PyInstaller output not found at dist/backend/mediaflow-server"
    exit 1
fi
echo "  ✓ Backend frozen: dist/backend/mediaflow-server"

# ─── Step 3: Generate AppIcon.icns ─────────────────────────────────────────
echo "[3/5] Generating app icon..."
ICON_SOURCE="$FRONTEND_DIR/MediaFlow/Resources/Assets.xcassets/AppIcon.appiconset"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Map PNG files to iconset naming convention (sips is built into macOS)
if [ -f "$ICON_SOURCE/icon_16.png" ]; then
    cp "$ICON_SOURCE/icon_16.png"   "$ICONSET_DIR/icon_16x16.png"
    cp "$ICON_SOURCE/icon_32.png"   "$ICONSET_DIR/icon_16x16@2x.png"
    cp "$ICON_SOURCE/icon_32.png"   "$ICONSET_DIR/icon_32x32.png"
    cp "$ICON_SOURCE/icon_64.png"   "$ICONSET_DIR/icon_32x32@2x.png"
    cp "$ICON_SOURCE/icon_128.png"  "$ICONSET_DIR/icon_128x128.png"
    cp "$ICON_SOURCE/icon_256.png"  "$ICONSET_DIR/icon_128x128@2x.png"
    cp "$ICON_SOURCE/icon_256.png"  "$ICONSET_DIR/icon_256x256.png"
    cp "$ICON_SOURCE/icon_512.png"  "$ICONSET_DIR/icon_256x256@2x.png"
    cp "$ICON_SOURCE/icon_512.png"  "$ICONSET_DIR/icon_512x512.png"
    cp "$ICON_SOURCE/icon_1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS/Resources/AppIcon.icns"
    echo "  ✓ AppIcon.icns generated"
else
    echo "  ⚠ No icon PNGs found, skipping icon generation"
fi
rm -rf "$ICONSET_DIR"

# ─── Step 4: Assemble the .app bundle ──────────────────────────────────────
echo "[4/5] Assembling app bundle..."

# Copy Swift binary
cp "$SWIFT_BIN" "$CONTENTS/MacOS/MediaFlow"
chmod +x "$CONTENTS/MacOS/MediaFlow"

# Copy SPM resource bundle (Bundle.module resources)
SPM_BUNDLE_DIR="$(swift build -c release --show-bin-path)"
SPM_BUNDLE=$(find "$SPM_BUNDLE_DIR" -name "MediaFlow_MediaFlow.bundle" -maxdepth 1 2>/dev/null | head -1)
if [ -n "$SPM_BUNDLE" ] && [ -d "$SPM_BUNDLE" ]; then
    cp -R "$SPM_BUNDLE" "$CONTENTS/Resources/"
    echo "  ✓ SPM resource bundle copied"
else
    echo "  ⚠ SPM resource bundle not found"
fi

# Copy frozen backend
cp -R "$BACKEND_DIR/dist/backend" "$CONTENTS/Resources/backend"
echo "  ✓ Backend copied to Resources/backend/"

# Write Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MediaFlow</string>
    <key>CFBundleDisplayName</key>
    <string>MediaFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.mediaflow.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>MediaFlow</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSuddenTerminationOK</key>
    <false/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST
echo "  ✓ Info.plist written"

# ─── Step 5: Code sign (ad-hoc) ────────────────────────────────────────────
echo "[5/5] Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR" 2>&1
echo "  ✓ Signed"

# ─── Done ───────────────────────────────────────────────────────────────────
echo ""
APP_SIZE=$(du -sh "$APP_DIR" | cut -f1)
echo "=== Build complete ==="
echo "  App:  $APP_DIR"
echo "  Size: $APP_SIZE"
echo ""
echo "To run: open $APP_DIR"
