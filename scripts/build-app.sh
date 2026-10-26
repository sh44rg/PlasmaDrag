#!/usr/bin/env bash
# Builds PlasmaDrag.app and installs it to ~/Applications.
# Usage: scripts/build-app.sh [--no-install]
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PlasmaDrag"
BUNDLE_ID="com.shaaravg.plasmadrag"
VERSION="1.0.0"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
echo "Built $APP_DIR"

if [[ "${1:-}" != "--no-install" ]]; then
    mkdir -p "$INSTALL_DIR"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$APP_DIR" "$INSTALL_DIR/"
    echo "Installed to $INSTALL_DIR/$APP_NAME.app"
fi
