#!/usr/bin/env bash
# build.sh: compile-check the app for iOS. Never installs, signs or deploys anything.
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM's default SwiftBuild engine cannot resolve the iphoneos platform on this
# host, so the deprecated 'native' engine is required (see docs/TOOLCHAIN_AUDIT.md).
exec swift build --build-system native --swift-sdk darwin --triple arm64-apple-ios "$@"
