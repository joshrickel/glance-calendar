<img src="docs/icon.png" width="96" alt="Glance icon" align="left" />

# Glance

**A tiny native macOS menu bar agenda.** Today and tomorrow across all your calendars, a live countdown to your next meeting, and a one-click Join button. Nothing else.

<br clear="left" />

## Why

Calendar apps keep growing features; the thing you actually do fifty times a day is *glance* — what's next, when, where's the link. Glance does only that job:

- **Menu bar countdown** — `Steve · 1:1 in 25m`, updating live. During a meeting it shows `· now`, after your last event it says `Done for today`.
- **One-click Join** — finds the Meet / Zoom / Teams / Webex link in the event and opens it.
- **Today + tomorrow agenda** — every calendar on your Mac, color-coded, past events dimmed and struck through.
- **Calendar toggles** — hide noisy calendars behind a collapsible row of chips; same-named calendars across accounts merge into one toggle, and duplicate events on shared calendars are deduped.

## What it deliberately doesn't do

No event creation or editing. No week/month grids. No notifications (macOS and your meeting tools already do that). No OAuth, no Google API, **no network code at all** — every calendar in System Settings → Internet Accounts arrives locally via EventKit. No Electron, no dependencies, no dock icon. Three Swift files.

The footer reads *"✦ Scheduling? Ask Claude"* — that's a static label, not an integration. It reflects the author's workflow (scheduling is delegated to an AI assistant, so this app never needs a create-event UI). Change the string in `AgendaView.swift` if it's not your workflow.

## Requirements

- Apple Silicon Mac, macOS 14+
- Xcode Command Line Tools (`xcode-select --install`)
- Your calendar accounts added in **System Settings → Internet Accounts** with Calendars enabled (if they show in Apple Calendar, they'll show in Glance)

## Install

```sh
git clone https://github.com/joshrickel/glance-calendar.git
cd glance-calendar
./scripts/setup-signing.sh   # one-time: stable signing so calendar access persists
./build.sh --install
```

This builds `Glance.app`, copies it to /Applications, launches it, and registers it as a login item. Grant **Full Access** when the calendar permission prompt appears. Building locally means no Gatekeeper warnings.

To build without installing: `./build.sh --run`.

### Signing & calendar permission

macOS ties calendar (TCC) permission to an app's code-signing identity. Ad-hoc signing (`codesign -s -`) produces a **new** identity on every build, so each rebuild looks like a different app and silently drops the permission. [`scripts/setup-signing.sh`](scripts/setup-signing.sh) creates a fixed, self-signed identity (`Glance Local Signing`) in your login keychain, so you grant calendar access **once** and it survives all future rebuilds. It requires OpenSSL 3 (`brew install openssl@3`) and is idempotent — run it once.

If you skip it, the build falls back to ad-hoc signing and macOS may re-prompt for calendar access after each rebuild. The certificate is self-signed and shows as untrusted — that's expected and fine for local use.

## How it works

| File | Purpose |
|------|---------|
| [`Glance/GlanceApp.swift`](Glance/GlanceApp.swift) | `@main` app delegate — owns the `NSStatusItem` (live countdown label) and the `NSPopover` that hosts the agenda |
| [`Glance/EventStore.swift`](Glance/EventStore.swift) | EventKit wrapper — auth, today+tomorrow fetch, change observer, join-URL detection, dedupe |
| [`Glance/AgendaView.swift`](Glance/AgendaView.swift) | The dropdown — header, calendar chips, hero next-event card, event lists |
| [`scripts/make-icon.swift`](scripts/make-icon.swift) | Draws the app icon programmatically with AppKit |

The menu bar item is a classic AppKit `NSStatusItem` rather than SwiftUI's `MenuBarExtra`, which drops its icon on display reconfiguration (docking, monitor connect/disconnect, sleep/wake). External calendar changes (phone, web, anything) arrive via `.EKEventStoreChanged` — no polling, no restart. Calendar visibility persists in `UserDefaults`. The countdown recomputes every 30 seconds.

## License

MIT — see [LICENSE](LICENSE).
