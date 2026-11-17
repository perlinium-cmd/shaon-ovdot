import Foundation

/// One write of a batch: all the writes of a `commit` happen together, or none of them (same as the website's
/// store.commit). Values are Firestore values; NSNull() writes null.
enum DocWrite {
    case set(_ col: String, _ id: String, _ data: [String: Any])
    case update(_ col: String, _ id: String, _ data: [String: Any])
    case delete(_ col: String, _ id: String)
}

/// Recycle bin, the same as the website (public/trash.js) and the phone: an employee, shift or payment is never only
/// deleted. A full copy of it, exactly as stored, goes to users/{uid}/trash/{col}__{id} ({col, id, data, deletedAt, by})
/// in the same batch as the delete, so nothing with money in it is gone for good.
enum Trash {
    static let cols: Set<String> = ["employees", "shifts", "payments"]
    /// Copies per batch (the rules check each copy against the live document, a few reads per copy).
    static let perBatch = 5
    /// Firestore allows 500 writes per batch.
    static let maxWrites = 450
    static func id(_ col: String, _ id: String) -> String { "\(col)__\(id)" }

    /// Cuts writes into batches, in order: at most `perBatch` copies and `maxWrites` writes each (a delete with a copy
    /// counts 2). `copies[i]` says whether write i carries a copy. Returns the indexes of each batch.
    static func plan(_ copies: [Bool]) -> [[Int]] {
        var out: [[Int]] = [], cur: [Int] = [], writes = 0, n = 0
        for (i, copy) in copies.enumerated() {
            let w = copy ? 2 : 1
            if writes > 0 && (writes + w > maxWrites || (copy && n == perBatch)) { out.append(cur); cur = []; writes = 0; n = 0 }
            cur.append(i); writes += w
            if copy { n += 1 }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
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
    /// The server refused to read this account's data (signed in with an account that has no access).
    var onDenied: (() -> Void)? { get set }
    func watchSettings(_ cb: @escaping (AppSettings) -> Void) -> () -> Void
    func saveSettings(_ s: AppSettings) async throws
    func watchEmployees(_ cb: @escaping ([Employee]) -> Void) -> () -> Void
    func addEmployee(_ e: Employee) async throws -> String
    func updateEmployee(_ e: Employee) async throws
    func deleteEmployee(_ id: String) async throws
    func watchShifts(month: String, _ cb: @escaping ([Shift]) -> Void) -> () -> Void
    func addShift(_ s: Shift) async throws -> String
    /// All payment records of one employee (every month). Changed only through `commit`.
    func watchPayments(empId: String, _ cb: @escaping ([Payment]) -> Void) -> () -> Void

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
