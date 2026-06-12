import SwiftUI

@main
struct GlanceApp: App {
    @StateObject private var store = EventStore()

    var body: some Scene {
        MenuBarExtra {
            AgendaView(store: store)
        } label: {
            // The menu bar defaults Labels to .iconOnly — force the title to render
            Label(store.menuBarTitle, systemImage: "calendar")
                .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
