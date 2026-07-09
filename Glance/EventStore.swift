import AppKit
import Combine
import EventKit
import Foundation

@MainActor
final class EventStore: ObservableObject {
    private var ek = EKEventStore()
    private var cancellables = Set<AnyCancellable>()
    private static let hiddenKey = "hiddenCalendarIDs"

    @Published var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var calendars: [EKCalendar] = []
    @Published private(set) var allTodayEvents: [EKEvent] = []
    @Published private(set) var allTomorrowEvents: [EKEvent] = []
    @Published var menuBarTitle: String = "Glance"
    @Published var lastSynced: Date?
    @Published var now: Date = Date()

    @Published var hiddenCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: Self.hiddenKey)
            updateTitle()
        }
    }

    init() {
        hiddenCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])

        // object: nil (not the ek instance) so the observer keeps firing even
        // after requestAccess() recreates the store.
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)

        Task { await requestAccess() }
    }

    // MARK: - Access

    func requestAccess() async {
        // Recreate the store so a permission change made in System Settings while
        // the app is running is actually picked up — the old instance can cache
        // the earlier (denied) decision.
        ek = EKEventStore()
        do {
            _ = try await ek.requestFullAccessToEvents()
        } catch {
            // status check below covers the denied case
        }
        authStatus = EKEventStore.authorizationStatus(for: .event)
        refresh()
    }

    // MARK: - Visibility

    /// Same-named calendars across accounts (Family ×3, Holidays ×2…) act as one unit.
    struct CalendarGroup: Identifiable {
        let title: String
        let calendars: [EKCalendar]
        var id: String { title }
    }

    var calendarGroups: [CalendarGroup] {
        Dictionary(grouping: calendars) { $0.title.trimmingCharacters(in: .whitespaces) }
            .map { CalendarGroup(title: $0.key, calendars: $0.value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func isHidden(_ group: CalendarGroup) -> Bool {
        group.calendars.allSatisfy { hiddenCalendarIDs.contains($0.calendarIdentifier) }
    }

    func toggle(_ group: CalendarGroup) {
        if isHidden(group) {
            for calendar in group.calendars { hiddenCalendarIDs.remove(calendar.calendarIdentifier) }
        } else {
            for calendar in group.calendars { hiddenCalendarIDs.insert(calendar.calendarIdentifier) }
        }
    }

    var hiddenGroupCount: Int {
        calendarGroups.filter(isHidden).count
    }

    var todayEvents: [EKEvent] { visibleDeduped(allTodayEvents) }
    var tomorrowEvents: [EKEvent] { visibleDeduped(allTomorrowEvents) }

    /// Visible events, cross-calendar duplicates removed, ordered for display:
    /// all-day events first, then timed events chronologically. (Sorting purely by
    /// startDate interleaves all-day events among timed ones — worse across time
    /// zones, where an all-day event's midnight can land mid-afternoon.)
    private func visibleDeduped(_ events: [EKEvent]) -> [EKEvent] {
        var seen = Set<String>()
        return events
            .filter { !hiddenCalendarIDs.contains($0.calendar.calendarIdentifier) }
            .filter { seen.insert(Self.dedupeKey($0)).inserted }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.startDate < b.startDate
            }
    }

    static func dedupeKey(_ event: EKEvent) -> String {
        "\(event.title ?? "")|\(event.startDate.timeIntervalSince1970)|\(event.endDate.timeIntervalSince1970)"
    }

    /// Total today count after dedupe, ignoring visibility — for the "N of M" header.
    var allTodayDedupedCount: Int {
        var seen = Set<String>()
        return allTodayEvents.filter { seen.insert(Self.dedupeKey($0)).inserted }.count
    }

    /// The current or next timed event today — drives the hero card.
    var heroEvent: EKEvent? {
        todayEvents.first { !$0.isAllDay && $0.endDate > now }
    }

    // MARK: - Fetch

    func refresh() {
        guard authStatus == .fullAccess else {
            updateTitle()
            return
        }
        calendars = ek.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        guard let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday),
              let endOfTomorrow = cal.date(byAdding: .day, value: 2, to: startOfToday) else { return }

        let predicate = ek.predicateForEvents(withStart: startOfToday, end: endOfTomorrow, calendars: nil)
        let events = ek.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        allTodayEvents = events.filter { $0.startDate < startOfTomorrow && $0.endDate > startOfToday }
        allTomorrowEvents = events.filter { $0.startDate < endOfTomorrow && $0.endDate > startOfTomorrow }

        lastSynced = Date()
        now = Date()
        fetchedDay = startOfToday
        ticksSinceRefresh = 0
        updateTitle()
    }

    private var fetchedDay: Date?
    private var ticksSinceRefresh = 0

    private func tick() {
        now = Date()

        // Self-heal: if access was granted in System Settings while running,
        // macOS doesn't notify us — re-request so the agenda appears without a
        // manual restart. (No prompt: once TCC has a decision this returns it.)
        if authStatus != .fullAccess {
            Task { await requestAccess() }
            return
        }

        ticksSinceRefresh += 1
        // Notifications cover real-time changes; refetch on day rollover (so
        // "today" is right at 7am even if nothing changed overnight) and every
        // 5 minutes as a safety net. EventKit fetches are local and cheap.
        if fetchedDay != Calendar.current.startOfDay(for: now) || ticksSinceRefresh >= 10 {
            refresh()
        } else {
            updateTitle()
        }
    }

    // MARK: - Menu bar title

    private func updateTitle() {
        let now = Date()
        let timed = todayEvents.filter { !$0.isAllDay }
        if let next = timed.first(where: { $0.startDate > now }) {
            menuBarTitle = "\(Self.truncate(next.title ?? "Event")) in \(Self.relativeString(from: now, to: next.startDate))"
        } else if let current = timed.first(where: { $0.startDate <= now && $0.endDate > now }) {
            menuBarTitle = "\(Self.truncate(current.title ?? "Event")) · now"
        } else if authStatus == .fullAccess {
            menuBarTitle = "Done for today"
        } else {
            menuBarTitle = "Glance"
        }
    }

    private static func truncate(_ title: String, max: Int = 18) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= max ? trimmed : String(trimmed.prefix(max)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Formatting helpers

    static func relativeString(from now: Date, to date: Date) -> String {
        let mins = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(mins)m"
    }

    // MARK: - Join URLs

    private static let conferenceDomains = [
        "meet.google.com", "zoom.us", "teams.microsoft.com",
        "webex.com", "whereby.com", "around.co", "meet.jit.si",
    ]

    static func joinURL(for event: EKEvent) -> URL? {
        var candidates: [URL] = []
        if let url = event.url { candidates.append(url) }
        for text in [event.location, event.notes].compactMap({ $0 }) {
            candidates.append(contentsOf: links(in: text))
        }
        if let conference = candidates.first(where: { url in
            guard let host = url.host else { return false }
            return conferenceDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
        }) {
            return conference
        }
        return candidates.first { $0.scheme == "https" || $0.scheme == "http" }
    }

    static func serviceName(for url: URL) -> String? {
        guard let host = url.host else { return nil }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams.microsoft") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("whereby") { return "Whereby" }
        return nil
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }
}
