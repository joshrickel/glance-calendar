import AppKit
import Combine
import EventKit
import Foundation

@MainActor
final class EventStore: ObservableObject {
    private let ek = EKEventStore()
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

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: ek)
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
        do {
            _ = try await ek.requestFullAccessToEvents()
        } catch {
            // status check below covers the denied case
        }
        authStatus = EKEventStore.authorizationStatus(for: .event)
        refresh()
    }

    // MARK: - Visibility

    func isHidden(_ calendar: EKCalendar) -> Bool {
        hiddenCalendarIDs.contains(calendar.calendarIdentifier)
    }

    func toggle(_ calendar: EKCalendar) {
        if hiddenCalendarIDs.contains(calendar.calendarIdentifier) {
            hiddenCalendarIDs.remove(calendar.calendarIdentifier)
        } else {
            hiddenCalendarIDs.insert(calendar.calendarIdentifier)
        }
    }

    var todayEvents: [EKEvent] { allTodayEvents.filter { !hiddenCalendarIDs.contains($0.calendar.calendarIdentifier) } }
    var tomorrowEvents: [EKEvent] { allTomorrowEvents.filter { !hiddenCalendarIDs.contains($0.calendar.calendarIdentifier) } }

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
        updateTitle()
    }

    private func tick() {
        now = Date()
        updateTitle()
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
