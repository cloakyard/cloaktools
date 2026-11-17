#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
probe_dir="$PWD/apps/macos/build/RoutingProbe.app"
mkdir -p "$probe_dir/Contents/MacOS"
cat > "$probe_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.cloakyard.routingprobe</string><key>CFBundleName</key><string>CloakTools Routing Probe</string><key>CFBundleExecutable</key><string>RoutingProbe</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Synthetic routing verification</string><key>CFBundleTypeRole</key><string>Viewer</string><key>CFBundleURLSchemes</key><array><string>http</string><string>https</string><string>mailto</string></array></dict></array></dict></plist>
PLIST
swiftc -swift-version 6 scripts/fixtures/RoutingProbe.swift -o "$probe_dir/Contents/MacOS/RoutingProbe"
codesign --force --sign - "$probe_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$probe_dir"
