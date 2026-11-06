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
        var minutes: Int? = nil   // real time between start and stop (a day or more can't be told from in/out alone)
    }
    var running: [String: Date] = [:]   // empId -> clock-in time
    var pending: [Pending] = []
}

enum QuickClock {
    /// Posted (Darwin notification) by the widget after queuing a shift, so a running app saves it right away.
    static let changedNotification = "com.perlinium.shaon.clockChanged"

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

    /// Read, change and write the file as one step. The widget and the app are separate processes: without
    /// coordination one of them could write over a change the other just made (a clocked shift lost or saved twice).
    private static func update<T>(_ change: (inout ClockState) -> T) -> T {
        guard let url else { var s = ClockState(); return change(&s) }
        var result: T?
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &err) { u in
            var s = (try? Data(contentsOf: u)).flatMap { try? JSONDecoder().decode(ClockState.self, from: $0) } ?? ClockState()
            result = change(&s)
            if let data = try? JSONEncoder().encode(s) { try? data.write(to: u, options: .atomic) }
        }
        if let result { return result }
        var s = load(); let r = change(&s); save(s); return r   // coordination unavailable: best effort
    }

    /// Clock in, or clock out and queue the finished shift. Returns the queued shift, if any.
    @discardableResult
    static func toggle(_ empId: String, now: Date = .now) -> ClockState.Pending? {
        update { s in
            guard let start = s.running.removeValue(forKey: empId) else {
                s.running[empId] = now
                return nil
            }
            // An accidental double tap shouldn't create a zero-length shift.
            guard now.timeIntervalSince(start) >= 60 else { return nil }
            let p = ClockState.Pending(empId: empId, date: dateStr(start), in: hhmm(start), out: hhmm(now),
                                       minutes: Int(now.timeIntervalSince(start) / 60))
            s.pending.append(p)
            return p
        }
    }

    /// App side: drop a queued shift once it's safely saved.
    static func removePending(_ id: UUID) {
        update { s in s.pending.removeAll { $0.id == id } }
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
