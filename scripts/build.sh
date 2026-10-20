#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
APP="$DIST/MacCam.app"
BUILD_DIR="$ROOT/.build"

echo "==> MacCam build"
echo "    Root: $ROOT"

command -v xcrun >/dev/null 2>&1 || {
  echo "error: Xcode Command Line Tools required."
  echo "       Run: xcode-select --install"
  exit 1
}

SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

mkdir -p "$BUILD_DIR" "$DIST"
rm -rf "$APP"

SOURCES=(
  MacCam/MacCamApp.swift
  MacCam/Features/ActivityLog.swift
  MacCam/Features/CameraGuard.swift
  MacCam/Features/CameraMonitor.swift
  MacCam/Features/GuardDecisionEngine.swift
  MacCam/Features/LoginItemService.swift
  MacCam/Features/PolicyStore.swift
  MacCam/Features/ProcessIdentifier.swift
  MacCam/UI/ActivityRow.swift
  MacCam/UI/DesignTokens.swift
  MacCam/UI/MenuBarView.swift
  MacCam/UI/SettingsSection.swift
  MacCam/UI/StatusIcon.swift
  MacCam/UI/VisualEffectBackground.swift
)

echo "==> Compiling (swiftc → $TARGET)"
xcrun swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -parse-as-library \
  -O \
  -whole-module-optimization \
  "${SOURCES[@]}" \
  -framework SwiftUI \
  -framework AppKit \
  -framework CoreMediaIO \
  -framework ServiceManagement \
  -framework UserNotifications \
  -o "$BUILD_DIR/MacCam"

echo "==> Assembling MacCam.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/MacCam" "$APP/Contents/MacOS/MacCam"
chmod +x "$APP/Contents/MacOS/MacCam"

# Bundle Info.plist with concrete values (no Xcode build settings).
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>MacCam</string>
	<key>CFBundleIdentifier</key>
	<string>com.maccam.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>MacCam</string>
	<key>CFBundleDisplayName</key>
	<string>MacCam</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 MacCam. Local privacy tool.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code sign"
codesign --force --deep --sign - "$APP" 2>/dev/null || true

# Clear quarantine if present (helps Gatekeeper after download/copy).
xattr -cr "$APP" 2>/dev/null || true

echo ""
echo "Build complete: $APP"
echo "Launch with:    open \"$APP\""
echo "Package zip:    ./scripts/package.sh"
