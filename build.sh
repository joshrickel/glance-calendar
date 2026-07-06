#!/bin/zsh
# Build Glance.app without an Xcode project.
# Usage: ./build.sh [--run]       build and launch from build/
#        ./build.sh [--install]   build, install to /Applications, launch, add login item
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
mkdir -p "$APP/Contents/Resources"
cp Glance/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Prefer a stable self-signed identity so calendar permission survives rebuilds
# (see scripts/setup-signing.sh). Fall back to ad-hoc if it isn't set up.
IDENTITY="Glance Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    SIGN_ID="$IDENTITY"
else
    SIGN_ID="-"
    echo "note: signing ad-hoc — run ./scripts/setup-signing.sh once so calendar access persists across rebuilds"
fi
codesign --force --sign "$SIGN_ID" --entitlements Glance/Glance.entitlements "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--run" ]]; then
    open "$APP"
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Glance 2>/dev/null || true
    rm -rf /Applications/Glance.app
    cp -R "$APP" /Applications/Glance.app
    open /Applications/Glance.app
    # Idempotent login item registration
    osascript -e 'tell application "System Events"
        if not (exists login item "Glance") then
            make login item at end with properties {path:"/Applications/Glance.app", hidden:false}
        end if
    end tell'
    echo "Installed /Applications/Glance.app and registered login item"
fi
