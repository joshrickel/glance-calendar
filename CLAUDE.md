# Glance — project instructions

Tiny native macOS menu bar agenda over EventKit. See [README.md](README.md) for
the product and [CHANGELOG.md](CHANGELOG.md) for history.

## Changelog discipline (standing rule)

**Every code change updates [CHANGELOG.md](CHANGELOG.md) in the same commit.** No
exceptions for code; docs-only or tooling-only tweaks may skip it.

- Add a bullet under an `## [Unreleased]` heading (create it above the latest
  release if absent), categorized **Added / Changed / Fixed / Removed**.
- On a release, rename `[Unreleased]` to the new version + date and bump
  `CFBundleShortVersionString` in [Glance/Info.plist](Glance/Info.plist) to match.
- Write bullets for a human reading history, not commit-message restatements.

## Build & run

- `./build.sh --install` — build, copy to /Applications, launch, register login item.
- `./build.sh --run` — build and launch from `build/` without installing.
- No Xcode project; `swiftc` compiles the three files in `Glance/`.

## Signing (don't regress this)

The build signs with a stable self-signed identity (`Glance Local Signing`) so
calendar (TCC) permission survives rebuilds — ad-hoc signing changes the code
hash every build and macOS wipes the grant. Run `./scripts/setup-signing.sh` once
per machine. Keep the bundle id (`com.joshrickel.glance`) and that identity stable.

## Design guardrails (from the original spec)

Glance does the *glance* job only. Do **not** add: event create/edit UI, OAuth or
any network code (EventKit is the entire data layer), week/month grids, or
notifications. The menu bar item must stay an AppKit `NSStatusItem`, not SwiftUI
`MenuBarExtra` (which drops its icon on display changes).
