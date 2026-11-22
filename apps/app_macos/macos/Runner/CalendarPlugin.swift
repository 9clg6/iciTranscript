import AppKit
import EventKit
import FlutterMacOS
import Foundation

// Apple documentation (read 2026-11-22):
// - https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)
//   (macOS 14.0+; prompts only the first time; completion on an arbitrary queue)
// - https://developer.apple.com/documentation/eventkit/ekeventstore/requestaccess(to:completion:)
//   (deprecated in macOS 14.0; used below 14 only)
// - https://developer.apple.com/documentation/eventkit/ekauthorizationstatus
//   (fullAccess / writeOnly are macOS 14+; `authorized` is the deprecated alias of fullAccess)
// - https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/ekeventstorechanged
//   (macOS 10.8+; posted on the main actor; the page names no posting object)
// - https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription
//   (required to read; macOS 14.0+; NSCalendarsUsageDescription kept for older systems)
// Signatures checked against the SDK headers (EventKit.framework/Headers).

/// Flutter plugin reading the user's calendars through EventKit.
///
/// Channel `com.icitranscript/calendar`:
/// - `accessStatus` -> `notDetermined` | `fullAccess` | `writeOnly` | `denied` | `restricted`
/// - `requestAccess` -> same string, after the system prompt (first time only)
/// - `calendars` -> [{id, title}]
/// - `events` {from, to (ms epoch), calendarIds: [String]?} -> [{id (unique per occurrence),
///   title, start, end, allDay, declined, calendarId, calendarTitle, attendees: [name]}]
/// - `openPrivacySettings` -> nil (System Settings › Privacy & Security › Calendars)
/// Swift -> Dart: `changed` on EKEventStoreChanged.
/// Nothing is logged: titles and names stay on this Mac.
class CalendarPlugin: NSObject, FlutterPlugin {

    private let store = EKEventStore()
    private let channel: FlutterMethodChannel
    private var observer: NSObjectProtocol?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,  // the page names no posting object
            queue: .main
        ) { [weak self] _ in
            self?.channel.invokeMethod("changed", arguments: nil)
        }
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/calendar",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(CalendarPlugin(channel: channel), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "accessStatus":
            result(statusName())
        case "requestAccess":
            requestAccess { result($0) }
        case "calendars":
            guard isFullAccess() else { return result([]) }
            result(store.calendars(for: .event).map {
                ["id": $0.calendarIdentifier, "title": $0.title]
            })
        case "events":
            guard let args = call.arguments as? [String: Any],
                  let from = (args["from"] as? NSNumber)?.doubleValue,
                  let to = (args["to"] as? NSNumber)?.doubleValue else {
                return result(FlutterError(code: "BAD_ARGS", message: "Missing from/to", details: nil))
            }
            guard isFullAccess() else {
                return result(FlutterError(code: "NO_ACCESS", message: "Calendar access not granted", details: nil))
            }
            result(events(from: from, to: to, calendarIds: args["calendarIds"] as? [String]))
        case "openPrivacySettings":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func statusName() -> String {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess: return "fullAccess"
            case .writeOnly: return "writeOnly"
            case .denied: return "denied"
            case .restricted: return "restricted"
            case .notDetermined: return "notDetermined"
            @unknown default: return "denied"
            }
        }
        switch status.rawValue {
        case EKAuthorizationStatus.notDetermined.rawValue: return "notDetermined"
        case EKAuthorizationStatus.restricted.rawValue: return "restricted"
        case EKAuthorizationStatus.denied.rawValue: return "denied"
        case 3: return "fullAccess"  // `authorized` before macOS 14 (same raw value)
        default: return "denied"
        }
    }

    private func isFullAccess() -> Bool { statusName() == "fullAccess" }

    private func requestAccess(_ done: @escaping (String) -> Void) {
        let finish: (Bool, Error?) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async {
                // Events fetched before the grant would stay empty otherwise.
                self?.store.reset()
                done(self?.statusName() ?? "denied")
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: finish)
        } else {
            store.requestAccess(to: .event, completion: finish)
        }
    }

    private func events(from: Double, to: Double, calendarIds: [String]?) -> [[String: Any]] {
        let calendars: [EKCalendar]? = calendarIds.map { ids in
            store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        }
        // An empty selection must read nothing, not every calendar (nil = all).
        if let calendars = calendars, calendars.isEmpty { return [] }
        let predicate = store.predicateForEvents(
            withStart: Date(timeIntervalSince1970: from / 1000),
            end: Date(timeIntervalSince1970: to / 1000),
            calendars: calendars
        )
        return store.events(matching: predicate).map(json)
    }

    private func json(_ event: EKEvent) -> [String: Any] {
        var participants = event.attendees ?? []
        if let organizer = event.organizer,
           !participants.contains(where: { $0.url == organizer.url }) {
            participants.append(organizer)
        }
        let declined = participants.contains {
            $0.isCurrentUser && $0.participantStatus == .declined
        }
        // eventIdentifier is shared by all occurrences of a recurring event;
        // the original occurrence date makes it unique and stable when one
        // occurrence is moved.
        let base = event.eventIdentifier ?? event.calendarItemIdentifier
        let occurrence = event.occurrenceDate ?? event.startDate ?? Date()
        return [
            "id": "\(base)@\(ms(occurrence))",
            "title": event.title ?? "",
            "start": ms(event.startDate),
            "end": ms(event.endDate),
            "allDay": event.isAllDay,
            "declined": declined,
            "calendarId": event.calendar?.calendarIdentifier ?? "",
            "calendarTitle": event.calendar?.title ?? "",
            // EventKit may give the address when there is no name; Dart drops
            // addresses but counts every participant.
            "attendees": participants.map { $0.name ?? "" },
        ]
    }

    private func ms(_ date: Date?) -> Int64 {
        Int64(((date ?? Date()).timeIntervalSince1970 * 1000).rounded())
    }
}
