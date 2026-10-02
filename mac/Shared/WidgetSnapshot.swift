import Foundation

/// What the app hands the widgets: a precomputed digest of the current month.
/// The widget extension can't talk to Firestore, so the app writes this into the shared App Group container.
struct WidgetSnapshot: Codable, Equatable {
    struct Emp: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var active = true
        var minutes: Int
        var pay: Double
        var paidPay: Double
        var shifts: Int
        var paidShifts: Int
        var last: Last?
        var unpaid: Double { round2(pay - paidPay) }
    }
    struct Last: Codable, Equatable {
        var date: String
        var `in`: String
        var out: String
    }

    var month: String                       // YYYY-MM the totals belong to
    var twelve: Bool
    var employees: [Emp]                    // active ones + archived ones with shifts this month
    var days: [String: [String: Int]]       // YYYY-MM-DD -> empId -> minutes (current + previous month)
    var updatedAt: Date

    var totalPay: Double { employees.reduce(0) { $0 + $1.pay } }
    var totalPaid: Double { employees.reduce(0) { $0 + $1.paidPay } }
    var totalMinutes: Int { employees.reduce(0) { $0 + $1.minutes } }
    var totalShifts: Int { employees.reduce(0) { $0 + $1.shifts } }
    var remaining: Double { round2(totalPay - totalPaid) }
    var paidFraction: Double { totalPay > 0 ? min(1, totalPaid / totalPay) : 0 }
    func emp(_ id: String) -> Emp? { employees.first { $0.id == id } }
}

/// Reads/writes the snapshot file in the App Group container shared by the app and the widget extension.
enum WidgetStore {
    static let monthKind = "MonthWidget"
    static let employeeKind = "EmployeeWidget"
    static let weekKind = "WeekWidget"
    static let quickKind = "QuickWidget"

    /// `$(TeamIdentifierPrefix)com.bee.shaon`, injected through Info.plist so it follows the signing team.
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "ShaonAppGroup") as? String }
    static var url: URL? {
        guard let id = groupID, !id.isEmpty,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        return dir.appending(path: "widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Returns true when the stored content actually changed (ignoring `updatedAt`).
    @discardableResult
    static func save(_ s: WidgetSnapshot?) -> Bool {
        guard let url else { return false }
        guard var s else {
            let existed = FileManager.default.fileExists(atPath: url.path)
            try? FileManager.default.removeItem(at: url)
            return existed
        }
        if var old = load() { old.updatedAt = s.updatedAt; if old == s { return false } }
        s.updatedAt = .now
        guard let data = try? JSONEncoder().encode(s) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
