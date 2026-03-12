#!/bin/bash
set -euo pipefail

# MediaFlow DMG Installer Builder
# Creates a professional macOS DMG with "drag to Applications" layout

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/MediaFlow.app"
DMG_NAME="MediaFlow"
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
DMG_TEMP="$BUILD_DIR/${DMG_NAME}_temp.dmg"
VOL_NAME="MediaFlow"
BG_WIDTH=660
BG_HEIGHT=400

echo "=== MediaFlow DMG Installer Builder ==="
echo ""

# ─── Step 0: Ensure MediaFlow.app exists ──────────────────────────────────
if [ ! -d "$APP_PATH" ]; then
    echo "MediaFlow.app not found, building it first..."
    echo ""
    "$SCRIPT_DIR/build_app.sh"
    echo ""
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: MediaFlow.app still not found after build"
    exit 1
fi

APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
echo "[1/5] Using app: $APP_PATH ($APP_SIZE)"

# ─── Step 1: Generate background image ────────────────────────────────────
echo "[2/5] Generating background image..."
BG_DIR="$BUILD_DIR/dmg_background"
BG_FILE="$BG_DIR/background.png"
mkdir -p "$BG_DIR"

# Use the backend venv Python if available, otherwise fall back to system Python
PYTHON3="$SCRIPT_DIR/backend/venv/bin/python3"
[ -x "$PYTHON3" ] || PYTHON3="$(command -v python3)"
"$PYTHON3" << PYEOF
from PIL import Image, ImageDraw
import os

W, H = 660, 400
img = Image.new("RGB", (W, H), (0xF0, 0xF0, 0xF0))
draw = ImageDraw.Draw(img)

# Subtle bottom edge
draw.line([(0, H - 1), (W, H - 1)], fill=(0xE0, 0xE0, 0xE0), width=1)

# Chevron arrow ">" centered at (330, 200)
cx, cy = 330, 200
size = 30
color = (0x88, 0x88, 0x88)
draw.line([(cx - 14, cy - size), (cx + 14, cy), (cx - 14, cy + size)], fill=color, width=5, joint="curve")

out_path = os.path.join("$BG_DIR", "background.png")
img.save(out_path, "PNG")
PYEOF

if [ ! -f "$BG_FILE" ]; then
    echo "ERROR: Background image generation failed"
    exit 1
fi
echo "  ✓ Background: $BG_FILE"

# ─── Step 2: Create read-write DMG ────────────────────────────────────────
echo "[3/5] Creating disk image..."

# Clean up any previous builds
rm -f "$DMG_TEMP" "$DMG_PATH"

# Unmount any leftover volume from previous runs
if [ -d "/Volumes/$VOL_NAME" ]; then
    hdiutil detach "/Volumes/$VOL_NAME" -quiet -force 2>/dev/null || true
    sleep 1
fi

# Calculate DMG size (app size + 20MB overhead)
APP_SIZE_KB=$(du -sk "$APP_PATH" | cut -f1)
DMG_SIZE_MB=$(( (APP_SIZE_KB / 1024) + 20 ))

# Create writable DMG
hdiutil create -size "${DMG_SIZE_MB}m" -fs HFS+ -volname "$VOL_NAME" "$DMG_TEMP" -quiet

# Mount it
MOUNT_OUTPUT=$(hdiutil attach "$DMG_TEMP" -readwrite -noverify -noautoopen)
DEVICE=$(echo "$MOUNT_OUTPUT" | grep '/dev/' | head -1 | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOL_NAME"

if [ ! -d "$MOUNT_POINT" ]; then
    echo "ERROR: Failed to mount DMG at $MOUNT_POINT"
    exit 1
fi
echo "  ✓ Mounted at $MOUNT_POINT"

# ─── Step 3: Populate DMG contents ────────────────────────────────────────
echo "[4/5] Populating DMG and configuring layout..."

# Copy app
cp -R "$APP_PATH" "$MOUNT_POINT/"

# Create Applications symlink
ln -s /Applications "$MOUNT_POINT/Applications"

# Add background image (hidden folder)
mkdir -p "$MOUNT_POINT/.background"
cp "$BG_FILE" "$MOUNT_POINT/.background/background.png"

# Volume icon: copy the app's icns as .VolumeIcon.icns and set the custom icon bit
ICNS_SRC="$APP_PATH/Contents/Resources/AppIcon.icns"
if [ -f "$ICNS_SRC" ]; then
    cp "$ICNS_SRC" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_POINT"
    echo "  ✓ Volume icon set"
fi

# Configure Finder window via AppleScript
# Note: Finder icon positions use top-left origin (y increases downward)
osascript << EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 760, 500}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.png"
        -- App on left, Applications on right
        set position of item "MediaFlow.app" of container window to {165, 190}
        set position of item "Applications" of container window to {495, 190}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# Ensure Finder writes .DS_Store
sync
sleep 2

# ─── Step 4: Convert to compressed read-only DMG ──────────────────────────
echo "[5/5] Converting to compressed DMG..."

# Unmount
hdiutil detach "$MOUNT_POINT" -quiet

# Convert to compressed read-only
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" -quiet

# Clean up temp DMG and background dir
rm -f "$DMG_TEMP"
rm -rf "$BG_DIR"

# Set the DMG file's own icon using fileicon
if command -v fileicon &>/dev/null && [ -f "$ICNS_SRC" ]; then
    fileicon set "$DMG_PATH" "$ICNS_SRC"
    echo "  ✓ DMG file icon set"
fi

# ─── Done ──────────────────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo ""
echo "=== DMG build complete ==="
echo "  DMG:  $DMG_PATH"
echo "  Size: $DMG_SIZE"
echo ""
echo "To test: open $DMG_PATH"
