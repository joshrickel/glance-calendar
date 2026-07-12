# Changelog

All notable changes to Glance are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); the project is pre-1.0 and
versioned informally.

## [Unreleased]

### Fixed
- **No menu bar icon after a restart.** The app now registers itself as a login
  item via `SMAppService` instead of a legacy AppleScript login item, which macOS
  could leave unapproved and skip at boot for a self-signed sandboxed app. The
  installer removes the old AppleScript item.

## [0.2.0] — 2026-07-08

Reliability pass — making Glance survive real-world daily use (traveling,
docking, rebuilds) without babysitting.

### Fixed
- **Menu bar icon vanishing.** Replaced SwiftUI's `MenuBarExtra` with a classic
  AppKit `NSStatusItem`. `MenuBarExtra` silently dropped its icon on display
  reconfiguration (docking, external monitor connect/disconnect, sleep/wake)
  while the process kept running.
- **Dropdown mis-positioning.** The agenda popover now anchors directly below the
  menu bar item and uses a fixed panel size, so the "Today" header and next-event
  card stay pinned and a packed day no longer pushes them off-screen.
- **Calendar permission wiped on every rebuild.** Ad-hoc signing changed the app's
  code hash each build, so macOS treated every rebuild as a new app and dropped
  the calendar (TCC) grant. A stable self-signed identity
  ([`scripts/setup-signing.sh`](scripts/setup-signing.sh)) keeps the signature
  constant — grant access once and it persists.
- **Event ordering.** All-day events now sort to the top of each day, then timed
  events chronologically (previously interleaved by start time, which read as
  out-of-order across time zones).

### Changed
- Self-healing calendar auth: the EventKit store is recreated on re-request and
  re-checked every 30s, so access granted in System Settings is picked up without
  a manual restart.
- Refetch on day rollover and every 5 minutes as a safety net, so "today" is
  correct each morning even with no overnight calendar changes.

## [0.1.0] — 2026-06-12

Initial build — a native macOS menu bar agenda that replaces Notion Calendar for
the glance job only.

### Added
- Menu bar countdown to the next event; today + tomorrow agenda across all local
  (EventKit) calendars — no network code.
- Next-event hero card with one-click **Join** for Meet / Zoom / Teams / Webex links.
- Calendar visibility chips behind a collapsible disclosure; same-named calendars
  across accounts merged into one toggle; duplicate events on shared calendars deduped.
- Past events dimmed and struck through; all-day events grouped; live countdown in
  the menu bar label.
- `./build.sh --install` — build, copy to /Applications, register a login item.
- App icon drawn programmatically ([`scripts/make-icon.swift`](scripts/make-icon.swift)),
  MIT license, and a public-facing README.
