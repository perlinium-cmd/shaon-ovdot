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
        var d = data; d["id"] = id
        guard JSONSerialization.isValidJSONObject(d), let json = try? JSONSerialization.data(withJSONObject: d) else { return nil }
        return try? JSONDecoder().decode(T.self, from: json)
    }
    private func encode<T: Encodable>(_ v: T, nulls: [String]) -> [String: Any] {
        guard let json = try? JSONEncoder().encode(v),
              var d = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return [:] }
        d["id"] = nil
        for k in nulls where d[k] == nil { d[k] = NSNull() }
        return d
    }
    private let shiftNulls = ["rate", "special", "paidAt", "paymentId"]

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
        for n in ["shifts", "payments"] {
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
}
