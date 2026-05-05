#!/bin/zsh
# potepote-pomodoro build script
# Compiles Swift source and packages it into a macOS .app bundle.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ぽてぽてポモドーロ"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "→ Cleaning $BUILD_DIR/"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "→ Compiling Swift source"
swiftc -O Sources/pomodoro.swift -o "$APP_DIR/Contents/MacOS/pomodoro"

echo "→ Copying resources"
cp Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/work_normal.png   "$APP_DIR/Contents/Resources/"
cp Resources/work_glasses.png  "$APP_DIR/Contents/Resources/"
cp Resources/break_relax.png   "$APP_DIR/Contents/Resources/"
cp Resources/AppIcon.icns      "$APP_DIR/Contents/Resources/"

echo "→ Cleaning extended attributes"
xattr -cr "$APP_DIR"

echo "→ Ad-hoc code signing"
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "Built: $APP_DIR"
echo "Open with: open '$APP_DIR'"
