# Glance

Tiny native macOS menu bar agenda — replaces Notion Calendar for the glance job only.

**The job:** glance at today/tomorrow across multiple Google calendars, next-event countdown in the menu bar, one-click join for meetings. Nothing else — no event creation, no OAuth, no network code, no Electron. All calendar data arrives locally via EventKit from accounts in System Settings → Internet Accounts.

## Build & run

```sh
./build.sh --run
```

Requires Xcode command line tools (swiftc). Produces `build/Glance.app`, ad-hoc signed with App Sandbox + Calendars entitlements. Grant **Full Access** when the calendar permission prompt appears.

Note: each rebuild re-signs with a new ad-hoc signature, so macOS may re-prompt for calendar access after rebuilding. Granting again is expected.

## Files

| File | Purpose |
|------|---------|
| `Glance/GlanceApp.swift` | `@main`, `MenuBarExtra` with live countdown label |
| `Glance/EventStore.swift` | EventKit wrapper: auth, today+tomorrow fetch, change observer, join-URL detection |
| `Glance/AgendaView.swift` | Dropdown UI: header, calendar chips, hero card, event lists, footer |
| `Glance/Info.plist` | `LSUIElement` (no dock icon), calendar usage description |
| `Glance/Glance.entitlements` | App Sandbox + calendars |

## Behavior

- Menu bar: `<next event> in 25m` → `<event> · now` during → `Done for today` after; refreshes every 30s
- Calendar chips toggle visibility, persisted in `UserDefaults` (`hiddenCalendarIDs`)
- Hero card shows the current/next timed event with a Join button when a Meet/Zoom/Teams/Webex URL is found in the event URL, location, or notes
- Past events dim to 45% with strikethrough; all-day events show "all day"
- External changes (Claude/n8n/phone) arrive via `.EKEventStoreChanged` — no restart needed

## Login at startup (v0.1: manual)

System Settings → General → Login Items → add `build/Glance.app`. (`SMAppService` checkbox is a v0.2 candidate.)
