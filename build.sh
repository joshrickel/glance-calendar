#!/bin/zsh
# Build Glance.app without an Xcode project.
# Usage: ./build.sh [--run]
set -euo pipefail

cd "$(dirname "$0")"

APP=build/Glance.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -parse-as-library \
    -target arm64-apple-macosx14.0 \
    Glance/GlanceApp.swift Glance/EventStore.swift Glance/AgendaView.swift \
    -framework SwiftUI -framework EventKit -framework AppKit \
    -o "$APP/Contents/MacOS/Glance"

cp Glance/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - --entitlements Glance/Glance.entitlements "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--run" ]]; then
    open "$APP"
fi
