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
    var isPaid: Bool { paid == true }
    var isOpen: Bool { open == true }
    var fromPhone: Bool { source == "phone" }

    /// Phone clock vs. server clock, in minutes. Large when the phone's clock is wrong
    /// or when she clocked in/out without reception and it synced later.
    var clockGapMinutes: Double? {
        guard fixedBy == nil else { return nil }   // times were changed on purpose
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
    var is12: Bool { timeFormat == "12" }
}
