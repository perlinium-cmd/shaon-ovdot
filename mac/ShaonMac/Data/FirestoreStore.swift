import Foundation
import FirebaseFirestore

/// Same collections and field names as the website (public/data.js): users/{uid}/settings|employees|shifts|payments.
@MainActor
final class FirestoreStore: DataStore {
    let isDemo = false
    private let db = Firestore.firestore()
    private let uid: String
    var onError: ((Error) -> Void)?

    init(uid: String) { self.uid = uid }

    private func col(_ n: String) -> CollectionReference { db.collection("users").document(uid).collection(n) }
    private func doc(_ n: String, _ id: String) -> DocumentReference { col(n).document(id) }

    // MARK: Codable <-> dictionary. The website stores explicit nulls, so nil optionals are written as NSNull.
    private func decode<T: Decodable>(_ type: T.Type, id: String, _ data: [String: Any]) -> T? {
        var d = data.mapValues { firestorePlain($0) }; d["id"] = id
        guard JSONSerialization.isValidJSONObject(d), let json = try? JSONSerialization.data(withJSONObject: d) else { return nil }
        return try? JSONDecoder().decode(T.self, from: json)
    }
    private func encode<T: Encodable>(_ v: T, nulls: [String]) -> [String: Any] {
        guard let json = try? JSONEncoder().encode(v),
              var d = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return [:] }
        d["id"] = nil
        for k in serverOwned { d[k] = nil }   // never overwrite server timestamps with numbers
        for k in nulls where d[k] == nil { d[k] = NSNull() }
        return d
    }
    private let shiftNulls = ["rate", "special", "paidAt", "paymentId"]
    private let serverOwned = ["syncedAt", "outSyncedAt", "pairedAt", "decidedAt"]

    // MARK: settings
    func watchSettings(_ cb: @escaping (AppSettings) -> Void) -> () -> Void {
        let l = doc("settings", "main").addSnapshotListener { [weak self] snap, err in
            if let err { self?.onError?(err); return }
            let d = snap?.data() ?? [:]
            cb(self?.decode(AppSettings.self, id: "main", d) ?? AppSettings())
        }
        return { l.remove() }
    }
    func saveSettings(_ s: AppSettings) async throws {
        try await doc("settings", "main").setData(encode(s, nulls: []), merge: true)
    }

    // MARK: employees
    func watchEmployees(_ cb: @escaping ([Employee]) -> Void) -> () -> Void {
        let l = col("employees").addSnapshotListener { [weak self] snap, err in
            if let err { self?.onError?(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(Employee.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func addEmployee(_ e: Employee) async throws -> String {
        let ref = col("employees").document()
        try await ref.setData(encode(e, nulls: ["rate"]))
        return ref.documentID
    }
    func updateEmployee(_ e: Employee) async throws {
        try await doc("employees", e.id).setData(encode(e, nulls: ["rate"]), merge: true)
    }
    func deleteEmployee(_ id: String) async throws {
        var refs = [doc("employees", id)]
        for n in ["shifts", "payments", "devices", "deviceKeys", "requests", "notices"] {
            refs += try await col(n).whereField("empId", isEqualTo: id).getDocuments().documents.map(\.reference)
        }
        for chunk in stride(from: 0, to: refs.count, by: 400).map({ Array(refs[$0..<min($0 + 400, refs.count)]) }) {
            let batch = db.batch(); chunk.forEach { batch.deleteDocument($0) }; try await batch.commit()
        }
    }

    // MARK: shifts
    func watchShifts(month: String, _ cb: @escaping ([Shift]) -> Void) -> () -> Void {
        let l = col("shifts").whereField("month", isEqualTo: month).addSnapshotListener { [weak self] snap, err in
            if let err { self?.onError?(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(Shift.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func addShift(_ s: Shift) async throws -> String {
        let ref = col("shifts").document()
        try await ref.setData(encode(s, nulls: shiftNulls))
        return ref.documentID
    }
    func updateShift(_ s: Shift) async throws { try await doc("shifts", s.id).setData(encode(s, nulls: shiftNulls), merge: true) }
    func restoreShifts(_ list: [Shift]) async throws {
        for chunk in stride(from: 0, to: list.count, by: 400).map({ Array(list[$0..<min($0 + 400, list.count)]) }) {
            let batch = db.batch(); chunk.forEach { batch.setData(encode($0, nulls: shiftNulls), forDocument: doc("shifts", $0.id)) }; try await batch.commit()
        }
    }
    func deleteShifts(_ ids: [String]) async throws {
        for chunk in stride(from: 0, to: ids.count, by: 400).map({ Array(ids[$0..<min($0 + 400, ids.count)]) }) {
            let batch = db.batch(); chunk.forEach { batch.deleteDocument(doc("shifts", $0)) }; try await batch.commit()
        }
    }
    func setPaid(_ ids: [String], paid: Bool) async throws {
        for chunk in stride(from: 0, to: ids.count, by: 400).map({ Array(ids[$0..<min($0 + 400, ids.count)]) }) {
            let batch = db.batch()
            chunk.forEach { batch.updateData(["paid": paid, "paidAt": paid ? Date().timeIntervalSince1970 * 1000 : NSNull()], forDocument: doc("shifts", $0)) }
            try await batch.commit()
        }
    }

    // MARK: rates
    func shiftsWithoutRate(empId: String) async throws -> [Shift] {
        try await col("shifts").whereField("empId", isEqualTo: empId).getDocuments().documents
            .compactMap { decode(Shift.self, id: $0.documentID, $0.data()) }
            .filter { $0.rate == nil }
    }
    func setRates(_ rates: [String: Double]) async throws {
        let items = Array(rates)
        for chunk in stride(from: 0, to: items.count, by: 400).map({ Array(items[$0..<min($0 + 400, items.count)]) }) {
            let batch = db.batch(); chunk.forEach { batch.updateData(["rate": $0.value], forDocument: doc("shifts", $0.key)) }; try await batch.commit()
        }
    }

    // MARK: phones
    func watchOpenShifts(_ cb: @escaping ([Shift]) -> Void) -> () -> Void {
        let l = col("shifts").whereField("open", isEqualTo: true).addSnapshotListener { [weak self] snap, err in
            if let err { self?.onError?(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(Shift.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func watchDevices(_ cb: @escaping ([Device]) -> Void) -> () -> Void {
        let l = col("devices").addSnapshotListener { [weak self] snap, err in
            if let err { self?.onError?(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(Device.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func watchRequests(_ cb: @escaping ([ShiftRequest]) -> Void) -> () -> Void {
        let l = col("requests").addSnapshotListener { [weak self] snap, err in
            if let err { self?.onError?(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(ShiftRequest.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func watchNotices(_ cb: @escaping ([Notice]) -> Void) -> () -> Void {
        let l = col("notices").order(by: "createdAt", descending: true).limit(to: 150).addSnapshotListener { [weak self] snap, err in
            if let err { self?.onError?(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(Notice.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func markNoticesSeen(_ ids: [String]) async throws {
        for chunk in stride(from: 0, to: ids.count, by: 400).map({ Array(ids[$0..<min($0 + 400, ids.count)]) }) {
            let batch = db.batch(); chunk.forEach { batch.updateData(["seen": true], forDocument: doc("notices", $0)) }; try await batch.commit()
        }
    }
    func createPairing(empId: String, empName: String) async throws -> Pairing {
        let p = Pairing(code: newPairingCode(), empId: empId, empName: empName, expiresAt: Date().addingTimeInterval(10 * 60))
        try await db.collection("pairings").document(p.code).setData([
            "ownerUid": uid, "empId": empId, "empName": empName,
            "expiresAt": Timestamp(date: p.expiresAt), "createdAt": FieldValue.serverTimestamp(),
        ])
        return p
    }
    func watchPairing(_ code: String, _ cb: @escaping (Bool) -> Void) -> () -> Void {
        let l = db.collection("pairings").document(code).addSnapshotListener { snap, _ in
            cb(snap?.data()?["usedBy"] != nil)
        }
        return { l.remove() }
    }
    func cancelPairing(_ code: String) async throws { try await db.collection("pairings").document(code).delete() }
    func disconnect(_ d: Device) async throws {
        let batch = db.batch()
        batch.deleteDocument(doc("devices", d.id))
        if let k = d.keyId { batch.deleteDocument(doc("deviceKeys", k)) }   // so it cannot reconnect by itself
        try await batch.commit()
    }
    func decide(_ r: ShiftRequest, approve: Bool, rate: Double) async throws {
        let reqRef = doc("requests", r.id)
        guard approve else {
            try await reqRef.updateData(["status": "rejected", "decidedAt": FieldValue.serverTimestamp()])
            return
        }
        let batch = db.batch()
        if r.type == "add" {
            let ref = col("shifts").document()
            batch.setData([
                "empId": r.empId, "date": r.date, "month": String(r.date.prefix(7)), "in": r.in, "out": r.out,
                "rate": rate, "special": NSNull(), "paid": false, "paidAt": NSNull(), "paymentId": NSNull(),
                "source": "request", "requestId": r.id, "createdAt": Date().timeIntervalSince1970 * 1000,
            ], forDocument: ref)
            batch.updateData(["status": "approved", "decidedAt": FieldValue.serverTimestamp(), "shiftId": ref.documentID], forDocument: reqRef)
        } else {
            guard let sid = r.shiftId else { throw StoreError.missingShift }
            let snap = try await doc("shifts", sid).getDocument()
            guard snap.exists, let old = decode(Shift.self, id: sid, snap.data() ?? [:]) else { throw StoreError.missingShift }
            if old.isPaid { throw StoreError.alreadyPaid }
            var u: [String: Any] = ["in": r.in, "date": r.date, "month": String(r.date.prefix(7)), "fixedBy": r.id]
            if old.rate == nil { u["rate"] = rate }
            if r.out.isEmpty {
                if old.isOpen, let ms = localMillis(date: r.date, time: r.in) { u["inAt"] = ms }   // the phone's running clock
            } else {
                u["out"] = r.out; u["open"] = false
            }
            batch.updateData(u, forDocument: doc("shifts", sid))
            batch.updateData(["status": "approved", "decidedAt": FieldValue.serverTimestamp()], forDocument: reqRef)
        }
        try await batch.commit()
    }
}

/// Firestore Timestamps (e.g. syncedAt written by the phone) -> ms numbers, so JSON decoding never drops a document.
func firestorePlain(_ v: Any) -> Any {
    switch v {
    case let t as Timestamp: return t.dateValue().timeIntervalSince1970 * 1000
    case let d as [String: Any]: return d.mapValues { firestorePlain($0) }
    case let a as [Any]: return a.map { firestorePlain($0) }
    default: return v
    }
}

/// Decodes a Firestore document's data the way FirestoreStore does (exposed for tests).
func decodeDoc<T: Decodable>(_ type: T.Type, id: String, _ data: [String: Any]) -> T? {
    var d = data.mapValues { firestorePlain($0) }; d["id"] = id
    guard JSONSerialization.isValidJSONObject(d), let json = try? JSONSerialization.data(withJSONObject: d) else { return nil }
    return try? JSONDecoder().decode(T.self, from: json)
}

enum StoreError: LocalizedError {
    case missingShift, alreadyPaid
    var errorDescription: String? {
        switch self {
        case .missingShift: "המשמרת שהבקשה מתייחסת אליה כבר לא קיימת"
        case .alreadyPaid: "המשמרת כבר סומנה כשולמה. בטל את סימון התשלום ואז אשר."
        }
    }
}

/// "2026-11-05" + "08:14" in the Mac's time zone -> ms since 1970.
func localMillis(date: String, time: String) -> Double? {
    let d = date.split(separator: "-").compactMap { Int($0) }, t = time.split(separator: ":").compactMap { Int($0) }
    guard d.count == 3, t.count == 2 else { return nil }
    return gregorian.date(from: DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1]))
        .map { $0.timeIntervalSince1970 * 1000 }
}
