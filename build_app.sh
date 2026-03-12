#!/bin/bash
set -euo pipefail

# MediaFlow App Builder
# Compiles the Swift package and Python backend, then assembles a proper
# .app bundle including the SPM resource bundle and bundled backend server.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR/frontend/MediaFlow"
BACKEND_DIR="$SCRIPT_DIR/backend"
BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/MediaFlow.app"
CONTENTS="$APP_PATH/Contents"
BUNDLE_ID="com.mediaflow.app"
VENV_DIR="$BACKEND_DIR/venv"

echo "=== MediaFlow App Builder ==="
echo ""

# ─── Step 1: Build Python backend ─────────────────────────────────────────
echo "[1/5] Building Python backend..."

# Create venv if missing
if [ ! -d "$VENV_DIR" ]; then
    echo "  Creating Python venv..."
    python3 -m venv "$VENV_DIR"
fi

echo "  Installing dependencies..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet -r "$BACKEND_DIR/requirements.txt"
"$VENV_DIR/bin/pip" install --quiet pyinstaller

echo "  Running PyInstaller..."
BACKEND_BUILD="$BUILD_DIR/backend-build"
BACKEND_DIST="$BUILD_DIR/backend-dist"

cd "$BACKEND_DIR"
"$VENV_DIR/bin/pyinstaller" \
    --onedir \
    --name mediaflow-server \
    --distpath "$BACKEND_DIST" \
    --workpath "$BACKEND_BUILD" \
    --specpath "$BUILD_DIR" \
    --noconfirm \
    --hidden-import uvicorn.logging \
    --hidden-import uvicorn.loops \
    --hidden-import uvicorn.loops.auto \
    --hidden-import uvicorn.loops.asyncio \
    --hidden-import uvicorn.protocols \
    --hidden-import uvicorn.protocols.http \
    --hidden-import uvicorn.protocols.http.auto \
    --hidden-import uvicorn.protocols.http.h11_impl \
    --hidden-import uvicorn.protocols.websockets \
    --hidden-import uvicorn.protocols.websockets.auto \
    --hidden-import uvicorn.protocols.websockets.websockets_impl \
    --hidden-import uvicorn.lifespan \
    --hidden-import uvicorn.lifespan.on \
    --hidden-import uvicorn.lifespan.off \
    --hidden-import sqlalchemy.dialects.sqlite \
    --hidden-import sqlalchemy.dialects.sqlite.aiosqlite \
    --hidden-import aiosqlite \
    --hidden-import asyncssh \
    --hidden-import aiosmtplib \
    --hidden-import fpdf2 \
    --hidden-import email.mime.text \
    --hidden-import email.mime.multipart \
    --hidden-import email.mime.base \
    --paths "$BACKEND_DIR" \
    run_server.py 2>&1 | grep -E "^(INFO|WARNING|ERROR|Building|Appending|COLLECT)" || true

BACKEND_BIN="$BACKEND_DIST/mediaflow-server/mediaflow-server"
if [ ! -f "$BACKEND_BIN" ]; then
    echo "ERROR: Backend binary not found at $BACKEND_BIN"
    exit 1
fi
echo "  ✓ Backend built"

# ─── Step 2: Build Swift frontend ─────────────────────────────────────────
echo "[2/5] Building Swift package (release)..."
cd "$FRONTEND_DIR"
swift build -c release 2>&1 | tail -5
SWIFT_BUILD_DIR="$FRONTEND_DIR/.build/release"

if [ ! -f "$SWIFT_BUILD_DIR/MediaFlow" ]; then
    echo "ERROR: Binary not found at $SWIFT_BUILD_DIR/MediaFlow"
    exit 1
fi
echo "  ✓ Swift build complete"

# ─── Step 3: Assemble app bundle ──────────────────────────────────────────
echo "[3/5] Assembling app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Swift binary
cp "$SWIFT_BUILD_DIR/MediaFlow" "$CONTENTS/MacOS/MediaFlow"
chmod +x "$CONTENTS/MacOS/MediaFlow"

# SPM resource bundle — must be in Contents/Resources for Bundle.module to find it
RESOURCE_BUNDLE="$SWIFT_BUILD_DIR/MediaFlow_MediaFlow.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/"
    echo "  ✓ MediaFlow_MediaFlow.bundle"
else
    echo "  WARNING: MediaFlow_MediaFlow.bundle not found — custom logo will not load"
fi

# Backend: copy the whole onedir output into Contents/Resources/backend/
# BackendProcessManager looks for Contents/Resources/backend/mediaflow-server
cp -R "$BACKEND_DIST/mediaflow-server/" "$CONTENTS/Resources/backend"
echo "  ✓ Backend binary bundled"

# Info.plist (substitute Xcode-style variables)
sed \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e "s/\$(EXECUTABLE_NAME)/MediaFlow/g" \
    "$FRONTEND_DIR/MediaFlow/Info.plist" > "$CONTENTS/Info.plist"
echo "  ✓ Info.plist"

# App icon: convert Assets.xcassets AppIcon to icns
ASSETS_DIR="$FRONTEND_DIR/MediaFlow/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -f "$ASSETS_DIR/icon_1024.png" ]; then
    ICONSET_TMP="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET_TMP"
    mkdir -p "$ICONSET_TMP"
    cp "$ASSETS_DIR/icon_16.png"   "$ICONSET_TMP/icon_16x16.png"
    cp "$ASSETS_DIR/icon_32.png"   "$ICONSET_TMP/icon_16x16@2x.png"
    cp "$ASSETS_DIR/icon_32.png"   "$ICONSET_TMP/icon_32x32.png"
    cp "$ASSETS_DIR/icon_64.png"   "$ICONSET_TMP/icon_32x32@2x.png"
    cp "$ASSETS_DIR/icon_128.png"  "$ICONSET_TMP/icon_128x128.png"
    cp "$ASSETS_DIR/icon_256.png"  "$ICONSET_TMP/icon_128x128@2x.png"
    cp "$ASSETS_DIR/icon_256.png"  "$ICONSET_TMP/icon_256x256.png"
    cp "$ASSETS_DIR/icon_512.png"  "$ICONSET_TMP/icon_256x256@2x.png"
    cp "$ASSETS_DIR/icon_512.png"  "$ICONSET_TMP/icon_512x512.png"
    cp "$ASSETS_DIR/icon_1024.png" "$ICONSET_TMP/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_TMP" -o "$CONTENTS/Resources/AppIcon.icns"
    rm -rf "$ICONSET_TMP"
    echo "  ✓ AppIcon.icns"
fi

echo "  ✓ App bundle: $APP_PATH"

# ─── Step 4: Ad-hoc code sign ─────────────────────────────────────────────
echo "[4/5] Code signing (ad-hoc)..."
# Sign the backend binary first, then the app as a whole
codesign --force --sign - "$CONTENTS/Resources/backend/mediaflow-server"
codesign --force --deep --sign - \
    --entitlements "$FRONTEND_DIR/MediaFlow/MediaFlow.entitlements" \
    "$APP_PATH"
echo "  ✓ Signed"

# ─── Step 5: Verify ───────────────────────────────────────────────────────
echo "[5/5] Verifying..."
codesign --verify --deep "$APP_PATH" && echo "  ✓ Signature valid"

APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
echo ""
echo "=== App build complete ==="
echo "  App:  $APP_PATH"
echo "  Size: $APP_SIZE"
echo ""
echo "To run: open $APP_PATH"
