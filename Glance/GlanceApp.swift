import AppKit
import Combine
import ServiceManagement
import SwiftUI

// Classic AppKit NSStatusItem instead of SwiftUI's MenuBarExtra. MenuBarExtra's
// status item is dropped by macOS on display reconfiguration (docking, external
// monitor connect/disconnect, sleep/wake) while the app keeps running — the icon
// silently disappears. NSStatusItem is managed by AppKit and survives all of that.
@main
enum GlanceMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = EventStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Glance")
            button.imagePosition = .imageLeading
            button.title = title(store.menuBarTitle)
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.contentViewController = NSHostingController(rootView: AgendaView(store: store))

        // Keep the menu bar text in sync with the countdown.
        store.$menuBarTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.statusItem.button?.title = self?.title(value) ?? value
            }
            .store(in: &cancellables)

        registerLoginItemIfNeeded()
    }

    /// Register as a login item via the modern SMAppService API. This creates a
    /// properly managed launch-at-login entry that starts reliably at boot —
    /// unlike a legacy AppleScript login item, which macOS can leave unapproved
    /// and silently skip for a self-signed sandboxed app. Only self-registers
    /// from /Applications so `--run` builds don't register a throwaway path.
    private func registerLoginItemIfNeeded() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            NSLog("Glance: login item registration failed: \(error)")
        }
    }

    private func title(_ value: String) -> String { " " + value }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Size the popover before showing so it anchors correctly under the
            // menu bar item (an unsized/zero-size popover mis-positions).
            popover.contentSize = NSSize(width: 380, height: store.authStatus == .fullAccess ? 520 : 170)
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
