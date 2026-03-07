#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION=$(sed -n 's/.*codeVersion = "\([^"]*\)".*/\1/p' Sources/HugoDesk/Models/AppVersion.swift | head -n 1)
fi

if [[ -z "$VERSION" ]]; then
  echo "failed to resolve version" >&2
  exit 1
fi

BUILD_UNIVERSAL="${BUILD_UNIVERSAL:-0}"
DEV_ID_APP_CERT="${DEV_ID_APP_CERT:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

APP_NAME="HugoDesk.app"
DMG_NAME="HugoDesk-v${VERSION}.dmg"
SRC_ZIP_NAME="HugoDesk-v${VERSION}-source.zip"

LATEST_DIR="$ROOT_DIR/latest"
ARCHIVE_DIR="$ROOT_DIR/HugoDeskArchive/versions/v${VERSION}"
STAGE_DIR="$(mktemp -d /tmp/hugodesk-release-stage.XXXXXX)"
APP_PATH="$STAGE_DIR/$APP_NAME"

mkdir -p "$LATEST_DIR" "$ARCHIVE_DIR"

echo "==> building release (arm64)"
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.clang-cache" swift build -c release

ARM64_BIN="$ROOT_DIR/.build/arm64-apple-macosx/release/HugoDesk"
ARM64_BUNDLE="$ROOT_DIR/.build/arm64-apple-macosx/release/HugoDesk_HugoDesk.bundle"

if [[ ! -f "$ARM64_BIN" || ! -d "$ARM64_BUNDLE" ]]; then
  echo "release artifacts missing" >&2
  exit 1
fi

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$ARM64_BIN" "$APP_PATH/Contents/MacOS/HugoDesk"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp -R "$ARM64_BUNDLE" "$APP_PATH/Contents/Resources/HugoDesk_HugoDesk.bundle"

if [[ "$BUILD_UNIVERSAL" == "1" ]]; then
  echo "==> building release (x86_64)"
  CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.clang-cache" swift build -c release --triple x86_64-apple-macosx13.0
  X64_BIN="$ROOT_DIR/.build/x86_64-apple-macosx/release/HugoDesk"
  if [[ -f "$X64_BIN" ]]; then
    lipo -create "$ARM64_BIN" "$X64_BIN" -output "$APP_PATH/Contents/MacOS/HugoDesk"
  else
    echo "x86_64 binary missing, keep arm64 only" >&2
  fi
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>HugoDesk</string>
  <key>CFBundleExecutable</key><string>HugoDesk</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.sexyfeifan.hugodesk</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>HugoDesk</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

cp "$ROOT_DIR/Docs/HugoDesk-使用说明.md" "$LATEST_DIR/HugoDesk-使用说明.md"
rm -rf "$LATEST_DIR/$APP_NAME"
cp -R "$APP_PATH" "$LATEST_DIR/$APP_NAME"

xattr -cr "$LATEST_DIR/$APP_NAME"

if [[ -n "$DEV_ID_APP_CERT" ]]; then
  echo "==> signing with Developer ID"
  codesign --force --deep --options runtime --timestamp --sign "$DEV_ID_APP_CERT" "$LATEST_DIR/$APP_NAME"
else
  echo "==> signing with ad-hoc certificate"
  codesign --force --deep --sign - --timestamp=none "$LATEST_DIR/$APP_NAME"
fi

echo "==> verifying signature"
codesign --verify --deep --strict --verbose=2 "$LATEST_DIR/$APP_NAME"

rm -f "$LATEST_DIR/$SRC_ZIP_NAME"
zip -r "$LATEST_DIR/$SRC_ZIP_NAME" .gitignore Assets CHANGELOG.md Docs Package.swift README.md Sources >/tmp/hugodesk_zip.log

rm -f "$LATEST_DIR/$DMG_NAME"
DMG_STAGE="$(mktemp -d /tmp/hugodesk-dmg-stage.XXXXXX)"
cp -R "$LATEST_DIR/$APP_NAME" "$DMG_STAGE/"
xattr -cr "$DMG_STAGE/$APP_NAME"
codesign --verify --deep --strict --verbose=2 "$DMG_STAGE/$APP_NAME"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "HugoDesk" -srcfolder "$DMG_STAGE" -ov -format UDZO "$LATEST_DIR/$DMG_NAME" >/tmp/hugodesk_dmg.log

if [[ -n "$DEV_ID_APP_CERT" && -n "$NOTARY_PROFILE" ]]; then
  echo "==> submitting dmg for notarization"
  xcrun notarytool submit "$LATEST_DIR/$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$LATEST_DIR/$DMG_NAME"
fi

rm -rf "$ARCHIVE_DIR/$APP_NAME"
cp -R "$LATEST_DIR/$APP_NAME" "$ARCHIVE_DIR/$APP_NAME"
xattr -cr "$ARCHIVE_DIR/$APP_NAME"
cp "$LATEST_DIR/$SRC_ZIP_NAME" "$ARCHIVE_DIR/$SRC_ZIP_NAME"
cp "$LATEST_DIR/$DMG_NAME" "$ARCHIVE_DIR/$DMG_NAME"
cp "$LATEST_DIR/HugoDesk-使用说明.md" "$ARCHIVE_DIR/HugoDesk-使用说明.md"

echo "==> done"
echo "version: $VERSION"
echo "app: $LATEST_DIR/$APP_NAME"
echo "dmg: $LATEST_DIR/$DMG_NAME"
