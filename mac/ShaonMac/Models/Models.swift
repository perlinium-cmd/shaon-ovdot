import Foundation

struct Special: Codable, Equatable {
    var rate: Double?
    var hours: Double?   // nil = whole shift
}

struct Employee: Codable, Identifiable, Equatable {
    var id: String = ""
    var name: String
    var rate: Double?    // nil = default rate
    var active: Bool? = true
    var createdAt: Double?
    var isActive: Bool { active != false }
}

struct Shift: Codable, Identifiable, Equatable {
    var id: String = ""
    var empId: String
    var date: String     // YYYY-MM-DD
    var month: String    // YYYY-MM
    var `in`: String     // HH:MM
    var out: String
    var rate: Double?
    var special: Special?
    var paid: Bool? = false
    var paidAt: Double?
    var paymentId: String?
    var createdAt: Double?
    var note: String?
    // Written by the employee's phone (see firestore.rules). Times are ms since 1970.
    var source: String?       // "phone" | "request" | nil (entered by the manager)
    var open: Bool?           // true while she is clocked in
    var inAt: Double?         // phone clock at clock-in
    var outAt: Double?        // phone clock at clock-out
    var syncedAt: Double?     // server clock when the clock-in reached the server (read only)
    var outSyncedAt: Double?  // server clock when the clock-out reached the server (read only)
    var deviceId: String?
    var fixedBy: String?      // id of the approved request that last changed this shift
    var requestId: String?    // for a shift added from a request
    var manual: Bool?         // typed in on the phone after the shift (same day, no approval needed)
    var edited: Bool?         // a time was changed on the phone on the day (no approval needed)
    var edits: Int?           // how many such changes (the phone allows two, then asks for approval)
    var isPaid: Bool { paid == true }
    var isOpen: Bool { open == true }
    var fromPhone: Bool { source == "phone" }
    var typedOnPhone: Bool { manual == true || edited == true }

    /// Phone clock vs. server clock, in minutes. Large when the phone's clock is wrong
    /// or when she clocked in/out without reception and it synced later.
    var clockGapMinutes: Double? {
        guard fixedBy == nil, !typedOnPhone else { return nil }   // times were changed on purpose
        var gaps: [Double] = []
        if let a = inAt, let b = syncedAt { gaps.append(abs(b - a) / 60000) }
        if let a = outAt, let b = outSyncedAt { gaps.append(abs(b - a) / 60000) }
        return gaps.max()
    }
    /// Minutes since clock-in, for a shift that is still open.
    func runningMinutes(now: Date = .now) -> Int? {
        guard isOpen else { return nil }
        if let inAt { return max(0, Int((now.timeIntervalSince1970 * 1000 - inAt) / 60000)) }
        return nil
    }
}

/// A phone connected to one employee (users/{uid}/devices/{id}, id = the phone's sign-in id).
struct Device: Codable, Identifiable, Equatable {
    var id: String = ""
    var empId: String
    var model: String?
    var pairedAt: Double?
    var keyId: String?
}

/// A request from the phone: fix a shift's times, or add a forgotten shift.
struct ShiftRequest: Codable, Identifiable, Equatable {
    var id: String = ""
    var empId: String
    var type: String          // "fix" | "add"
    var shiftId: String?
    var date: String
    var `in`: String
    var out: String           // "" = fixing only the clock-in of a running shift
    var note: String?
    var status: String        // "pending" | "approved" | "rejected" | "cancelled"
    var createdAt: Double?
    var decidedAt: Double?
    var isPending: Bool { status == "pending" }
}

/// Something the phone saved without asking (users/{uid}/notices/{id}), so the manager hears about it:
/// a forgotten shift typed in on the day it ended ("manual"), or a clock-in / clock-out changed on the day ("fix").
/// The phone can add these but never read them (firestore.rules).
struct Notice: Codable, Identifiable, Equatable {
    var id: String = ""
    var empId: String
    var type: String          // "manual" | "fix"
    var shiftId: String
    var date: String
    var `in`: String
    var out: String           // "" = the shift is still running
    var prevIn: String?       // "fix": the times before the change
    var prevOut: String?      // "" = it was still running
    var edit: Int?            // "fix": 1st or 2nd change of this shift
    var createdAt: Double?
    var deviceId: String?
    var seen: Bool?
    var isSeen: Bool { seen == true }
    /// A running shift closed at the time she really left (she forgot to clock out).
    var closedShift: Bool { type == "fix" && (prevOut ?? "").isEmpty && !out.isEmpty }
    var movedIn: Bool { type == "fix" && prevIn != nil && prevIn != `in` }
    var movedOut: Bool { type == "fix" && !(prevOut ?? "").isEmpty && prevOut != out }
}

/// A short-lived code that connects a phone (pairings/{code}).
struct Pairing: Equatable {
    var code: String
    var empId: String
    var empName: String
    var expiresAt: Date
    /// "K7QM4XPA" -> "K7QM-4XPA"
    var display: String { String(code.prefix(4)) + "-" + String(code.dropFirst(4)) }
    var qrPayload: String { "shaon://pair/\(code)" }
}

/// 8 characters from 32 unambiguous ones (no 0/O, 1/I) = 40 random bits, from the system's secure generator.
func newPairingCode() -> String {
    let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    var rng = SystemRandomNumberGenerator()
    return String((0..<8).map { _ in alphabet[Int(rng.next(upperBound: UInt32(alphabet.count)))] })
}

struct Payment: Codable, Identifiable, Equatable {
    var id: String = ""
    var empId: String
    var date: String
    var amount: Double
    var method: String
    var shiftIds: [String]?
    var createdAt: Double?
}

struct AppSettings: Codable, Equatable {
    var defaultRate: Double?
    var timeFormat: String?   // "24" | "12"
    var empOrder: [String]?   // personal order of the employee list (same fields as the website: public/reorder.js)
    var empPinned: [String]?  // employees pinned to the top
    var is12: Bool { timeFormat == "12" }
}

// MARK: lenient decoding
// A field with an unexpected type (e.g. a rate saved as text) reads as "not set" instead of failing the whole
// document — otherwise that shift would silently vanish from the Mac's lists and totals while the website shows it.

private extension KeyedDecodingContainer {
    func opt<T: Decodable>(_ type: T.Type, _ key: Key) -> T? { (try? decodeIfPresent(type, forKey: key)) ?? nil }
    func str(_ key: Key) -> String { opt(String.self, key) ?? "" }
}

extension Special {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(rate: c.opt(Double.self, .rate), hours: c.opt(Double.self, .hours))
    }
}

extension Employee {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: c.str(.id), name: c.str(.name), rate: c.opt(Double.self, .rate), active: c.opt(Bool.self, .active),
                  createdAt: c.opt(Double.self, .createdAt))
    }
}

extension Shift {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: c.str(.id), empId: c.str(.empId), date: c.str(.date), month: c.str(.month), in: c.str(.in), out: c.str(.out),
                  rate: c.opt(Double.self, .rate), special: c.opt(Special.self, .special), paid: c.opt(Bool.self, .paid),
                  paidAt: c.opt(Double.self, .paidAt), paymentId: c.opt(String.self, .paymentId), createdAt: c.opt(Double.self, .createdAt),
                  note: c.opt(String.self, .note), source: c.opt(String.self, .source), open: c.opt(Bool.self, .open),
                  inAt: c.opt(Double.self, .inAt), outAt: c.opt(Double.self, .outAt), syncedAt: c.opt(Double.self, .syncedAt),
                  outSyncedAt: c.opt(Double.self, .outSyncedAt), deviceId: c.opt(String.self, .deviceId), fixedBy: c.opt(String.self, .fixedBy),
                  requestId: c.opt(String.self, .requestId), manual: c.opt(Bool.self, .manual), edited: c.opt(Bool.self, .edited),
                  edits: c.opt(Int.self, .edits))
    }
}

extension Payment {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: c.str(.id), empId: c.str(.empId), date: c.str(.date), amount: c.opt(Double.self, .amount) ?? 0,
                  method: c.str(.method), shiftIds: c.opt([String].self, .shiftIds), createdAt: c.opt(Double.self, .createdAt))
    }
}

// MARK: personal order + pinning of the employee list (the same rules as public/reorder.js)

struct EmpLayout: Equatable {
    var pinned: [String]
    var rest: [String]

    /// Employees in the saved order, pinned first. New ones (not in `order` yet) go to the end of their group, by name.
    init(_ emps: [Employee], order: [String]?, pinned: [String]?) {
        let pos = Dictionary((order ?? []).enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let pin = Set(pinned ?? [])
        let sorted = emps.sorted { a, b in
            let ra = pos[a.id] ?? Int.max, rb = pos[b.id] ?? Int.max
            if ra != rb { return ra < rb }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
        self.pinned = sorted.filter { pin.contains($0.id) }.map(\.id)
        self.rest = sorted.filter { !pin.contains($0.id) }.map(\.id)
    }
    init(pinned: [String], rest: [String]) { self.pinned = pinned; self.rest = rest }

    /// Pin → end of the pinned group. Unpin → top of the others.
    func togglingPin(_ id: String) -> EmpLayout {
        let p = pinned.filter { $0 != id }, r = rest.filter { $0 != id }
        return pinned.contains(id) ? EmpLayout(pinned: p, rest: [id] + r) : EmpLayout(pinned: p + [id], rest: r)
    }

    /// One step (-1 up / +1 down). Stepping over the line between the groups pins / unpins; the order stays.
    func moving(_ id: String, by delta: Int) -> EmpLayout {
        if let i = pinned.firstIndex(of: id) {
            if delta > 0 && i == pinned.count - 1 { return EmpLayout(pinned: Array(pinned.dropLast()), rest: [id] + rest) }
            let j = i + delta
            guard pinned.indices.contains(j) else { return self }
            var p = pinned; p.swapAt(i, j)
            return EmpLayout(pinned: p, rest: rest)
        }
        guard let i = rest.firstIndex(of: id) else { return self }
        if delta < 0 && i == 0 && !pinned.isEmpty { return EmpLayout(pinned: pinned + [id], rest: Array(rest.dropFirst())) }
        let j = i + delta
        guard rest.indices.contains(j) else { return self }
        var r = rest; r.swapAt(i, j)
        return EmpLayout(pinned: pinned, rest: r)
    }

    /// Drag & drop inside one group (SwiftUI `onMove` semantics).
    func moved(pinnedGroup: Bool, from: IndexSet, to: Int) -> EmpLayout {
        var list = pinnedGroup ? pinned : rest
        let moving = from.sorted().map { list[$0] }
        let before = from.filter { $0 < to }.count
        for i in from.sorted(by: >) { list.remove(at: i) }
        list.insert(contentsOf: moving, at: to - before)
        return pinnedGroup ? EmpLayout(pinned: list, rest: rest) : EmpLayout(pinned: pinned, rest: list)
    }

    /// What to save. Saved ids that are not on screen right now keep their place at the end.
    func settingsValues(previousOrder: [String]?) -> (order: [String], pinned: [String]) {
        let shown = pinned + rest, seen = Set(shown)
        return (shown + (previousOrder ?? []).filter { !seen.contains($0) }, pinned)
    }
}
