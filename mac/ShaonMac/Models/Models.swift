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
    var isPaid: Bool { paid == true }
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
