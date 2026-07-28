#!/bin/bash

# Configuration
APP_NAME="MP4Merger"
EXECUTABLE_NAME="MP4Merger"
OUTPUT_DIR="."

echo "🚀 Building ${APP_NAME} in Release mode..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed."
    exit 1
fi

# Get the build path dynamically
BUILD_PATH=$(swift build -c release --show-bin-path)
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"

echo "📦 Creating App Bundle structure at ${APP_BUNDLE}..."

# Clean up previous build
if [ -d "${APP_BUNDLE}" ]; then
    rm -rf "${APP_BUNDLE}"
fi

# Create directories
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
echo "📋 Copying executable..."
cp "${BUILD_PATH}/${EXECUTABLE_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Copy FFmpeg if present in project root, or fallback to system one for testing
echo "🎬 Bundling FFmpeg..."
if [ -f "ffmpeg" ]; then
    echo "   Using local ffmpeg binary."
    cp "ffmpeg" "${APP_BUNDLE}/Contents/Resources/"
elif [ -f "/opt/homebrew/bin/ffmpeg" ]; then
    echo "   Using system ffmpeg binary (Dynamic! Not for distribution!)."
    cp "/opt/homebrew/bin/ffmpeg" "${APP_BUNDLE}/Contents/Resources/"
else
    echo "⚠️  FFmpeg not found! App may crash."
fi

# Copy Icon if present
echo "icon Bundling Icon..."
if [ -f "AppIcon.icns" ]; then
    echo "   Using AppIcon.icns."
    cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
    ICON_ENTRY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    echo "⚠️  AppIcon.icns not found! Using default icon."
    ICON_ENTRY=""
fi

# Create Info.plist
echo "📝 Creating Info.plist..."
cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.93</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ja</string>
    </array>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    ${ICON_ENTRY}
</dict>
</plist>
EOF

# Apply Ad-Hoc Code Signature with Entitlements
echo "🔏 Signing with Entitlements..."
codesign --force --deep --sign - --entitlements Entitlements.plist "${APP_BUNDLE}" --options runtime


# Optional: Add PkgInfo
echo "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

echo "✅ Done! ${APP_NAME}.app is ready."
echo "open ${OUTPUT_DIR}"
#
//  build_app.sh
//  MP4Merger
//

