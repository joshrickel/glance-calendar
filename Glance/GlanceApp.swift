import SwiftUI

@main
struct GlanceApp: App {
    @StateObject private var store = EventStore()

    var body: some Scene {
        MenuBarExtra {
            AgendaView(store: store)
        } label: {
            Label(store.menuBarTitle, systemImage: "calendar")
        }
        .menuBarExtraStyle(.window)
    }
}
