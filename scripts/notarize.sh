#!/bin/bash
# Archive, sign with Developer ID, notarize, staple, and verify MP4Merger.
#
# The bundled ffmpeg executable (Contents/Resources/ffmpeg) must carry its own
# Developer ID signature with the hardened runtime, or the notary service
# rejects the app -- it is signed explicitly, then the app seal is re-signed.
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
IDENTITY="Developer ID Application: (redacted) (7JSPUB92B6)"
BUILD_DIR="build"

echo "==> 1/7 Archiving (Release)"
rm -rf "$BUILD_DIR"
xcodebuild -project MP4Merger.xcodeproj -scheme MP4Merger -configuration Release \
  archive -archivePath "$BUILD_DIR/MP4Merger.xcarchive" -quiet

echo "==> 2/7 Exporting with Developer ID signing"
cat > "$BUILD_DIR/ExportOptions.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>7JSPUB92B6</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$BUILD_DIR/MP4Merger.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" -quiet

APP="$BUILD_DIR/export/MP4Merger.app"

echo "==> 3/7 Signing bundled ffmpeg (hardened runtime + timestamp)"
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" "$APP/Contents/Resources/ffmpeg"

echo "==> 4/7 Re-signing the app bundle"
codesign --force --options runtime --timestamp \
  --entitlements MP4Merger.entitlements \
  --sign "$IDENTITY" "$APP"

echo "==> 5/7 Zipping and submitting to Apple notary service"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/MP4Merger.zip"
xcrun notarytool submit "$BUILD_DIR/MP4Merger.zip" \
  --keychain-profile "$PROFILE" --wait

echo "==> 6/7 Stapling the notarization ticket"
xcrun stapler staple "$APP"

echo "==> 7/7 Verifying"
spctl -a -vv "$APP"
xcrun stapler validate "$APP"

echo
echo "Done: $APP"
echo "Install with: rm -rf /Applications/MP4Merger/MP4Merger.app && ditto '$APP' /Applications/MP4Merger/MP4Merger.app"
