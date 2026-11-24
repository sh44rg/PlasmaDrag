#!/usr/bin/env bash
# Builds PlasmaDrag.app, installs it to /Applications and launches it.
# Usage: scripts/build-app.sh [--no-install]
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PlasmaDrag"
BUNDLE_ID="com.shaaravg.plasmadrag"
VERSION="1.1.0"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
COPYRIGHT="Copyright © $(date +%Y) Shaarav Gunsi"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
OLD_INSTALL="$HOME/Applications/$APP_NAME.app"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

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
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>
    <string>$COPYRIGHT</string>
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

    # Earlier versions installed to ~/Applications; don't leave a stale copy
    # around for Spotlight or Launch Services to pick up.
    if [[ -d "$OLD_INSTALL" ]]; then
        rm -rf "$OLD_INSTALL"
        echo "Removed old copy at $OLD_INSTALL"
    fi

    open "$INSTALL_DIR/$APP_NAME.app"
fi
