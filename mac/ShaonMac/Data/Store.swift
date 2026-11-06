import Foundation

/// One write of a batch: all the writes of a `commit` happen together, or none of them (same as the website's
/// store.commit). Values are Firestore values; NSNull() writes null.
enum DocWrite {
    case set(_ col: String, _ id: String, _ data: [String: Any])
    case update(_ col: String, _ id: String, _ data: [String: Any])
    case delete(_ col: String, _ id: String)
}

/// A document as it was (data nil = it did not exist), so a change can be undone exactly.
struct DocSnapshot {
    let col: String
    let id: String
    let data: [String: Any]?
}

enum StoreError: LocalizedError, Equatable {
    case missingShift, alreadyPaid, offline
    var errorDescription: String? {
        switch self {
        case .missingShift: "המשמרת שהבקשה מתייחסת אליה כבר לא קיימת"
        case .alreadyPaid: "המשמרת כבר סומנה כשולמה. בטל את סימון התשלום ואז אשר."
        case .offline: "אין חיבור לאינטרנט, ולפעולה הזו צריך נתונים מהשרת (כדי שהחשבון יישאר מדויק – למשל שמשמרות קודמות יישארו בתעריף שבו עבדו). שום דבר לא השתנה. נסה שוב כשיש חיבור."
        }
    }
}

/// Same shape as the JS data layer (public/data.js): live listeners + simple writes.
@MainActor
protocol DataStore: AnyObject {
    var isDemo: Bool { get }
    /// Problems to show the user: a listener that failed, or a write the server refused after it was saved here.
    var onProblem: ((String) -> Void)? { get set }
    func watchSettings(_ cb: @escaping (AppSettings) -> Void) -> () -> Void
    func saveSettings(_ s: AppSettings) async throws
    func watchEmployees(_ cb: @escaping ([Employee]) -> Void) -> () -> Void
    func addEmployee(_ e: Employee) async throws -> String
    func updateEmployee(_ e: Employee) async throws
    func deleteEmployee(_ id: String) async throws
    func watchShifts(month: String, _ cb: @escaping ([Shift]) -> Void) -> () -> Void
    func addShift(_ s: Shift) async throws -> String

    // Writes that must happen together (payments + the shifts they cover), and exact undo.
    func newId(_ col: String) -> String
    func commit(_ writes: [DocWrite]) async throws
    func snapshot(_ refs: [(col: String, id: String)]) async throws -> [DocSnapshot]

    // Rates: lock a rate onto shifts that have none yet (before a rate change). Must see every shift: throws
    // StoreError.offline when it can't ask the server.
    func shiftsWithoutRate(empId: String) async throws -> [Shift]
    func setRates(_ rates: [String: Double]) async throws

    // Employee phones
    func watchOpenShifts(_ cb: @escaping ([Shift]) -> Void) -> () -> Void
    func watchDevices(_ cb: @escaping ([Device]) -> Void) -> () -> Void
    func watchRequests(_ cb: @escaping ([ShiftRequest]) -> Void) -> () -> Void
    func createPairing(empId: String, empName: String) async throws -> Pairing
    /// Called with true once a phone has used the code.
    func watchPairing(_ code: String, _ cb: @escaping (Bool) -> Void) -> () -> Void
    func cancelPairing(_ code: String) async throws
    func disconnect(_ d: Device) async throws
    /// Approve (applies the change to the shift) or reject a request.
    func decide(_ r: ShiftRequest, approve: Bool, rate: Double) async throws
    /// Changes the phone saved without approval (newest first).
    func watchNotices(_ cb: @escaping ([Notice]) -> Void) -> () -> Void
    func markNoticesSeen(_ ids: [String]) async throws
}

extension DataStore {
    /// Writes the documents back exactly as they were (nil = delete).
    func restore(_ snaps: [DocSnapshot]) async throws {
        try await commit(snaps.map { s in
            if let d = s.data { return DocWrite.set(s.col, s.id, d) }
            return DocWrite.delete(s.col, s.id)
        })
    }
}
