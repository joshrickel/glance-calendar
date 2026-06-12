import AppKit
import EventKit
import SwiftUI

struct AgendaView: View {
    @ObservedObject var store: EventStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.authStatus == .fullAccess {
                header
                if !store.calendars.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(store.calendars, id: \.calendarIdentifier) { calendar in
                            CalendarChip(calendar: calendar, isOn: !store.isHidden(calendar)) {
                                store.toggle(calendar)
                            }
                        }
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        agenda
                    }
                }
                .frame(maxHeight: 460)
                footer
            } else {
                accessPrompt
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.system(size: 15, weight: .medium))
            Spacer()
            Text(headerSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var headerSummary: String {
        let visible = store.todayEvents.count
        let total = store.allTodayEvents.count
        let hidden = store.calendars.filter(store.isHidden).count
        var summary = visible == total ? "\(total) events" : "\(visible) of \(total) events"
        if hidden > 0 {
            summary += " · \(hidden) calendar\(hidden == 1 ? "" : "s") hidden"
        }
        return summary
    }

    // MARK: - Agenda body

    @ViewBuilder
    private var agenda: some View {
        let hero = store.heroEvent

        if let hero {
            HeroCard(event: hero, now: store.now)
        }

        let remainingToday = store.todayEvents.filter { $0 !== hero }
        if remainingToday.isEmpty && hero == nil {
            Text("No events today")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(remainingToday.enumerated()), id: \.offset) { _, event in
                    EventRow(event: event, now: store.now)
                }
            }
        }

        Text("Tomorrow")
            .font(.system(size: 15, weight: .medium))
            .padding(.top, 4)

        if store.tomorrowEvents.isEmpty {
            Text("No events tomorrow")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(store.tomorrowEvents.enumerated()), id: \.offset) { _, event in
                    EventRow(event: event, now: store.now, dimPast: false)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("✦ Scheduling? Ask Claude")
            Spacer()
            Text(syncedText)
        }
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
    }

    private var syncedText: String {
        guard let synced = store.lastSynced else { return "" }
        let mins = Int(store.now.timeIntervalSince(synced) / 60)
        return mins < 1 ? "synced just now" : "synced \(mins)m ago"
    }

    // MARK: - Access prompt

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar access needed")
                .font(.system(size: 15, weight: .medium))
            Text("Glance reads your calendars locally via EventKit. Grant Full Access to Calendars to see your agenda.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Try Again") {
                    Task { await store.requestAccess() }
                }
            }
        }
    }
}

// MARK: - Calendar chip

private struct CalendarChip: View {
    let calendar: EKCalendar
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(calendar.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? calendarColor(calendar) : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule().fill(isOn ? calendarColor(calendar).opacity(0.12) : Color.gray.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help(isOn ? "Hide \(calendar.title)" : "Show \(calendar.title)")
    }
}

// MARK: - Hero card

private struct HeroCard: View {
    let event: EKEvent
    let now: Date

    var body: some View {
        let joinURL = EventStore.joinURL(for: event)

        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(calendarColor(event.calendar))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? "Event")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                Text(subtitle(joinURL: joinURL))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(countdown)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let joinURL {
                Button("Join") { NSWorkspace.shared.open(joinURL) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
    }

    private func subtitle(joinURL: URL?) -> String {
        var text = timeRange(event)
        if let joinURL, let service = EventStore.serviceName(for: joinURL) {
            text += " · \(service)"
        } else if let location = event.location, !location.isEmpty, !location.hasPrefix("http") {
            text += " · \(location)"
        }
        return text
    }

    private var countdown: String {
        if event.startDate > now {
            return "starts in \(EventStore.relativeString(from: now, to: event.startDate))"
        }
        return "ends in \(EventStore.relativeString(from: now, to: event.endDate))"
    }
}

// MARK: - Event row

private struct EventRow: View {
    let event: EKEvent
    let now: Date
    var dimPast: Bool = true

    var body: some View {
        let isPast = dimPast && !event.isAllDay && event.endDate <= now

        HStack(spacing: 8) {
            Text(event.isAllDay ? "all day" : startTime(event))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Circle()
                .fill(calendarColor(event.calendar))
                .frame(width: 8, height: 8)
            Text(event.title ?? "Event")
                .font(.system(size: 12))
                .strikethrough(isPast)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .opacity(isPast ? 0.45 : 1.0)
    }
}

// MARK: - Shared helpers

private func calendarColor(_ calendar: EKCalendar?) -> Color {
    guard let nsColor = calendar?.color else { return .gray }
    return Color(nsColor: nsColor)
}

private let intervalFormatter: DateIntervalFormatter = {
    let formatter = DateIntervalFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

private func timeRange(_ event: EKEvent) -> String {
    if event.isAllDay { return "all day" }
    return intervalFormatter.string(from: event.startDate, to: event.endDate)
}

private func startTime(_ event: EKEvent) -> String {
    timeFormatter.string(from: event.startDate)
}

// MARK: - Flow layout for chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 352
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
