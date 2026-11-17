#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/../apps/macos"
GIT_CONFIG_COUNT=0 xcodegen generate
GIT_CONFIG_COUNT=0 xcodebuild -project CloakTools.xcodeproj -scheme CloakTools -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/Verify build "$@"
