import Foundation

/// Start/stop clock driven from the "רישום מהיר" widget.
/// The widget extension can't reach Firestore, so finished shifts wait in the App Group container
/// until the app picks them up (immediately when it's running, otherwise on next launch).
struct ClockState: Codable, Equatable {
    struct Pending: Codable, Equatable, Identifiable {
        var id = UUID()
        var empId: String
        var date: String   // YYYY-MM-DD of the start
        var `in`: String   // HH:MM
        var out: String
    }
    var running: [String: Date] = [:]   // empId -> clock-in time
    var pending: [Pending] = []
}

enum QuickClock {
    /// Posted (Darwin notification) by the widget after queuing a shift, so a running app saves it right away.
    static let changedNotification = "com.bee.shaon.clockChanged"

    static var url: URL? { WidgetStore.url?.deletingLastPathComponent().appending(path: "clock.json") }

    static func load() -> ClockState {
        guard let url, let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(ClockState.self, from: data) else { return ClockState() }
        return s
    }
    static func save(_ s: ClockState) {
        guard let url, let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Clock in, or clock out and queue the finished shift. Returns the queued shift, if any.
    @discardableResult
    static func toggle(_ empId: String, now: Date = .now) -> ClockState.Pending? {
        var s = load()
        defer { save(s) }
        guard let start = s.running.removeValue(forKey: empId) else {
            s.running[empId] = now
            return nil
        }
        // An accidental double tap shouldn't create a zero-length shift.
        guard now.timeIntervalSince(start) >= 60 else { return nil }
        let p = ClockState.Pending(empId: empId, date: dateStr(start), in: hhmm(start), out: hhmm(now))
        s.pending.append(p)
        return p
    }

    /// App side: drop a queued shift once it's safely saved.
    static func removePending(_ id: UUID) {
        var s = load()
        s.pending.removeAll { $0.id == id }
        save(s)
    }

    static func postChanged() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(changedNotification as CFString), nil, nil, true)
    }

    static func hhmm(_ d: Date) -> String {
        let c = gregorian.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }
}
