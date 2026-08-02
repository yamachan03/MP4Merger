#!/bin/bash
# Archive, sign with Developer ID, notarize, staple, and verify MP4Merger.
#
# FFmpeg is intentionally NOT bundled (license: the evermeet.cx/Homebrew
# builds are GPL). The app locates or downloads ffmpeg at runtime. If a
# stray Resources/ffmpeg is found in the export, this script aborts.
#
# Prerequisites (one-time; shared with TagFinder):
#   1. A "Developer ID Application" certificate in the keychain
#   2. notarytool credentials stored as the "tagfinder-notary" keychain profile
#
# Usage: ./scripts/notarize.sh
# Output: build/export/MP4Merger.app (signed, notarized, stapled)

set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROFILE="tagfinder-notary"
TEAM_ID="7JSPUB92B6"
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application.*($TEAM_ID)" | head -1 | sed -E 's/.*"(.+)"/\1/')
if [ -z "$IDENTITY" ]; then
  echo "No 'Developer ID Application' identity for team $TEAM_ID found in keychain." >&2
  exit 1
fi
BUILD_DIR="build"

echo "==> 1/8 Archiving (Release)"
rm -rf "$BUILD_DIR"
xcodebuild -project MP4Merger.xcodeproj -scheme MP4Merger -configuration Release \
  archive -archivePath "$BUILD_DIR/MP4Merger.xcarchive" -quiet

echo "==> 2/8 Exporting with Developer ID signing"
cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$BUILD_DIR/MP4Merger.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" -quiet

APP="$BUILD_DIR/export/MP4Merger.app"

echo "==> 3/8 Verifying no ffmpeg is bundled"
if [ -f "$APP/Contents/Resources/ffmpeg" ]; then
  echo "ERROR: Resources/ffmpeg found in the exported app." >&2
  echo "FFmpeg must not be bundled (GPL build). Remove it from the Xcode project." >&2
  exit 1
fi

echo "==> 4/8 Re-signing the app bundle"
codesign --force --options runtime --timestamp \
  --entitlements MP4Merger.entitlements \
  --sign "$IDENTITY" "$APP"

echo "==> 5/8 Zipping and submitting to Apple notary service"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/MP4Merger-notary-submission.zip"
xcrun notarytool submit "$BUILD_DIR/MP4Merger-notary-submission.zip" \
  --keychain-profile "$PROFILE" --wait

echo "==> 6/8 Stapling the notarization ticket"
xcrun stapler staple "$APP"

echo "==> 7/8 Verifying"
spctl -a -vv "$APP"
xcrun stapler validate "$APP"

echo "==> 8/8 Creating release zip (stapled app)"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/MP4Merger.zip"

echo
echo "Done: $APP"
echo "Release asset (upload this to GitHub Releases): $BUILD_DIR/MP4Merger.zip"
echo "Install with: rm -rf /Applications/MP4Merger/MP4Merger.app && ditto '$APP' /Applications/MP4Merger/MP4Merger.app"
