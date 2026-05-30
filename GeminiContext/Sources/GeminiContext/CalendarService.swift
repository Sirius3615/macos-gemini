import Foundation
import EventKit

/// Wraps macOS EventKit for calendar read access.
/// Used by the AI tool `get_calendar_events` to answer schedule questions.
final class CalendarService {

    static let shared = CalendarService()

    private let store = EKEventStore()

    /// Whether calendar access has been granted.
    var isAuthorized: Bool {
        if #available(macOS 14.0, *) {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        } else {
            return EKEventStore.authorizationStatus(for: .event) == .authorized
        }
    }

    private init() {}

    // MARK: - Permission

    /// Requests calendar read access. Returns true if granted.
    @discardableResult
    func requestAccess() async -> Bool {
        if isAuthorized { return true }

        do {
            if #available(macOS 14.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            print("[CalendarService] Error requesting access: \(error)")
            return false
        }
    }

    // MARK: - Fetch Events

    /// Fetches events from all calendars within the date range.
    func fetchEvents(from startDate: Date, to endDate: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = store.events(matching: predicate)
        return events.sorted { $0.startDate < $1.startDate }
    }

    /// Fetches events and returns a formatted string for the AI tool response.
    func fetchEventsFormatted(from startDate: Date, to endDate: Date) -> String {
        guard isAuthorized else {
            return "Error: Calendar access has not been granted. The user needs to grant Calendar permission in System Settings > Privacy & Security > Calendars."
        }

        let events = fetchEvents(from: startDate, to: endDate)

        if events.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "No events found between \(formatter.string(from: startDate)) and \(formatter.string(from: endDate))."
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d"

        var lines: [String] = ["Calendar events (\(events.count) found):"]
        var currentDay = ""

        for event in events {
            let day = dateFormatter.string(from: event.startDate)
            if day != currentDay {
                currentDay = day
                lines.append("\n── \(day) ──")
            }

            if event.isAllDay {
                lines.append("  🗓 [All day] \(event.title ?? "Untitled")")
            } else {
                let start = timeFormatter.string(from: event.startDate)
                let end = timeFormatter.string(from: event.endDate)
                lines.append("  🕐 \(start)–\(end)  \(event.title ?? "Untitled")")
            }

            if let location = event.location, !location.isEmpty {
                lines.append("    📍 \(location)")
            }

            if let calName = event.calendar?.title {
                lines.append("    📅 \(calName)")
            }

            if let notes = event.notes, !notes.isEmpty {
                let trimmed = notes.prefix(200)
                lines.append("    📝 \(trimmed)\(notes.count > 200 ? "..." : "")")
            }
        }

        return lines.joined(separator: "\n")
    }
}
