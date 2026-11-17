import Foundation
import FirebaseFirestore

/// Same collections and field names as the website (public/data.js): users/{uid}/settings|employees|shifts|payments.
@MainActor
final class FirestoreStore: DataStore {
    let isDemo = false
    private let db = Firestore.firestore()
    private let uid: String
    var onProblem: ((String) -> Void)?
    var onDenied: (() -> Void)?

    init(uid: String) { self.uid = uid }

    private func col(_ n: String) -> CollectionReference { db.collection("users").document(uid).collection(n) }
    private func doc(_ n: String, _ id: String) -> DocumentReference { col(n).document(id) }
    private func listenerFailed(_ e: Error) {
        print(e)
        let ns = e as NSError
        if ns.domain == FirestoreErrorDomain && ns.code == FirestoreErrorCode.permissionDenied.rawValue { onDenied?(); return }
        onProblem?("בעיה בחיבור לנתונים")
    }

    /// Firestore first answers from this Mac's copy, which right after sign-in may be empty. Showing that would flash
    /// "add your first employee" before the real data arrives, so an empty first answer from the copy is held back
    /// until the server answers (or 4 seconds pass, e.g. without internet). Everything after that passes as it comes.
    @MainActor private final class FirstAnswerGate {
        private var passed = false
        func pass(fromCache: Bool, empty: Bool, _ emit: @escaping () -> Void) {
            if !passed && fromCache && empty {
                Task { @MainActor in try? await Task.sleep(for: .seconds(4)); if !self.passed { self.passed = true; emit() } }
                return
            }
            passed = true
            emit()
        }
    }

    // MARK: writes that never hang offline
    // Firestore keeps a write on this Mac at once (in its on-disk cache, so it survives quitting) and sends it when it
    // can, but only reports back once the server has it — without internet that can be hours. Waiting for that would
    // leave the form full and invite a second click (a duplicate shift). So wait briefly: after that the write is safe
    // here and syncs by itself. A failure that arrives later is reported through onProblem.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var done = false
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        var isDone: Bool { lock.lock(); defer { lock.unlock() }; return done }
    }
    private func settle(_ start: (@escaping @Sendable (Error?) -> Void) -> Void) async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            start { [weak self] err in
                if let err {
                    if once.take() { c.resume(throwing: err) }
                    else { Task { @MainActor in print(err); self?.onProblem?("שינוי אחד לא נשמר בשרת – כדאי לבדוק את הרשימה") } }
                } else if once.take() { c.resume() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if once.take() { c.resume() } }
        }
    }
    private func write(_ batch: WriteBatch) async throws { try await settle { done in batch.commit { done($0) } } }

    // MARK: Codable <-> dictionary. The website stores explicit nulls, so nil optionals are written as NSNull.
    private func decode<T: Decodable>(_ type: T.Type, id: String, _ data: [String: Any]) -> T? { decodeDoc(type, id: id, data) }
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
        let gate = FirstAnswerGate()
        let l = doc("settings", "main").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, err in
            if let err { self?.listenerFailed(err); return }
            guard let snap else { return }
            gate.pass(fromCache: snap.metadata.isFromCache, empty: !snap.exists) {
                cb(self?.decode(AppSettings.self, id: "main", snap.data() ?? [:]) ?? AppSettings())
            }
        }
        return { l.remove() }
    }
    func saveSettings(_ s: AppSettings) async throws {
        let b = db.batch(); b.setData(encode(s, nulls: []), forDocument: doc("settings", "main"), merge: true)
        try await write(b)
    }

    // MARK: employees
    func watchEmployees(_ cb: @escaping ([Employee]) -> Void) -> () -> Void {
        let gate = FirstAnswerGate()
        let l = col("employees").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, err in
            if let err { self?.listenerFailed(err); return }
            guard let snap else { return }
            gate.pass(fromCache: snap.metadata.isFromCache, empty: snap.isEmpty) {
                cb(snap.documents.compactMap { self?.decode(Employee.self, id: $0.documentID, $0.data()) })
            }
        }
        return { l.remove() }
    }
    func addEmployee(_ e: Employee) async throws -> String {
        let ref = col("employees").document()
        let b = db.batch(); b.setData(encode(e, nulls: ["rate"]), forDocument: ref)
        try await write(b)
        return ref.documentID
    }
    func updateEmployee(_ e: Employee) async throws {
        let b = db.batch(); b.setData(encode(e, nulls: ["rate"]), forDocument: doc("employees", e.id), merge: true)
        try await write(b)
    }
    func deleteEmployee(_ id: String) async throws {
        var writes: [DocWrite] = []
        var known: [String: [String: Any]] = [:]   // already read from the server: no second read for the copy
        for n in ["shifts", "payments", "devices", "deviceKeys", "requests", "notices"] {
            for d in try await serverDocs(col(n).whereField("empId", isEqualTo: id)) {
                writes.append(.delete(n, d.documentID))
                if Trash.cols.contains(n) { known["\(n)/\(d.documentID)"] = d.data() }
            }
        }
        // The employee last: if a batch fails on the way, she is still listed and the delete can be tried again.
        writes.append(.delete("employees", id))
        try await writeWithTrash(writes, known: known)
    }

    // MARK: shifts
    func watchShifts(month: String, _ cb: @escaping ([Shift]) -> Void) -> () -> Void {
        let gate = FirstAnswerGate()
        let l = col("shifts").whereField("month", isEqualTo: month).addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, err in
            if let err { self?.listenerFailed(err); return }
            guard let snap else { return }
            gate.pass(fromCache: snap.metadata.isFromCache, empty: snap.isEmpty) {
                cb(snap.documents.compactMap { self?.decode(Shift.self, id: $0.documentID, $0.data()) })
            }
        }
        return { l.remove() }
    }
    func watchPayments(empId: String, _ cb: @escaping ([Payment]) -> Void) -> () -> Void {
        let l = col("payments").whereField("empId", isEqualTo: empId).addSnapshotListener { [weak self] snap, err in
            if let err { self?.listenerFailed(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(Payment.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func addShift(_ s: Shift) async throws -> String {
        let ref = s.id.isEmpty ? col("shifts").document() : doc("shifts", s.id)
        let b = db.batch(); b.setData(encode(s, nulls: shiftNulls), forDocument: ref)
        try await write(b)
        return ref.documentID
    }

    // MARK: batches + undo
    func newId(_ c: String) -> String { col(c).document().documentID }
    func commit(_ writes: [DocWrite]) async throws { try await writeWithTrash(writes) }

    /// Every write that may delete goes through here (public/trash.js writeWithTrash). Each copy is read before anything
    /// is written, so a read that fails (offline, a document not on this Mac) changes nothing. A document that no longer
    /// exists is deleted without a copy. `known`: "col/id" → data already read from the server.
    private func writeWithTrash(_ writes: [DocWrite], known: [String: [String: Any]] = [:]) async throws {
        var copies: [[String: Any]?] = []
        for w in writes {
            guard case let .delete(c, id) = w, Trash.cols.contains(c) else { copies.append(nil); continue }
            if let d = known["\(c)/\(id)"] { copies.append(d) } else { copies.append(try await snapshot([(c, id)]).first?.data) }
        }
        for group in Trash.plan(copies.map { $0 != nil }) {
            let b = db.batch()
            for i in group {
                switch writes[i] {
                case let .set(c, id, data): b.setData(data, forDocument: doc(c, id))
                case let .update(c, id, data): b.updateData(data, forDocument: doc(c, id))
                case let .delete(c, id):
                    if let copy = copies[i] {
                        b.setData(["col": c, "id": id, "data": copy, "deletedAt": FieldValue.serverTimestamp(), "by": uid],
                                  forDocument: doc("trash", Trash.id(c, id)))
                    }
                    b.deleteDocument(doc(c, id))
                }
            }
            try await write(b)
        }
    }
    /// Reads this Mac's copy first, so undo works offline; asks the server only for what isn't here.
    /// Payment records are the exception: nothing on this Mac listens to them, so a copy here may be old (changed on the
    /// website since), and the shifts and sum taken out of a record must come from the record as it is now. They are read
    /// from the server when there is a connection (without one: the copy here, the best there is).
    func snapshot(_ refs: [(col: String, id: String)]) async throws -> [DocSnapshot] {
        var out: [DocSnapshot] = []
        for r in refs {
            let ref = doc(r.col, r.id)
            let snap: DocumentSnapshot
            do {
                if r.col == "payments" { snap = try await ref.getDocument() }
                else {
                    do { snap = try await ref.getDocument(source: .cache) } catch { snap = try await ref.getDocument() }
                }
            } catch let e as NSError where e.domain == FirestoreErrorDomain && e.code == FirestoreErrorCode.unavailable.rawValue {
                throw StoreError.offline
            }
            out.append(DocSnapshot(col: r.col, id: r.id, data: snap.exists ? snap.data() : nil))
        }
        return out
    }

    // MARK: rates
    /// Every matching document, from the server (never a partial list from this Mac's copy); StoreError.offline without internet.
    private func serverDocs(_ q: Query) async throws -> [QueryDocumentSnapshot] {
        do { return try await q.getDocuments(source: .server).documents }
        catch let e as NSError where e.domain == FirestoreErrorDomain && e.code == FirestoreErrorCode.unavailable.rawValue { throw StoreError.offline }
    }
    func shiftsWithoutRate(empId: String) async throws -> [Shift] {
        // From the server: this Mac's copy may lack months it never opened, and a missed shift would change price.
        try await serverDocs(col("shifts").whereField("empId", isEqualTo: empId))
            .compactMap { decode(Shift.self, id: $0.documentID, $0.data()) }.filter { $0.rate == nil }
    }
    func setRates(_ rates: [String: Double]) async throws {
        try await commit(rates.map { .update("shifts", $0.key, ["rate": $0.value]) })
    }

    // MARK: phones
    func watchOpenShifts(_ cb: @escaping ([Shift]) -> Void) -> () -> Void {
        let l = col("shifts").whereField("open", isEqualTo: true).addSnapshotListener { [weak self] snap, err in
            if let err { self?.listenerFailed(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(Shift.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func watchDevices(_ cb: @escaping ([Device]) -> Void) -> () -> Void {
        let l = col("devices").addSnapshotListener { [weak self] snap, err in
            if let err { self?.listenerFailed(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(Device.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func watchRequests(_ cb: @escaping ([ShiftRequest]) -> Void) -> () -> Void {
        let l = col("requests").addSnapshotListener { [weak self] snap, err in
            if let err { self?.listenerFailed(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(ShiftRequest.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func watchNotices(_ cb: @escaping ([Notice]) -> Void) -> () -> Void {
        let l = col("notices").order(by: "createdAt", descending: true).limit(to: 150).addSnapshotListener { [weak self] snap, err in
            if let err { self?.listenerFailed(err); return }
            cb((snap?.documents ?? []).compactMap { self?.decode(Notice.self, id: $0.documentID, $0.data()) })
        }
        return { l.remove() }
    }
    func markNoticesSeen(_ ids: [String]) async throws {
        try await commit(ids.map { .update("notices", $0, ["seen": true]) })
    }
    func createPairing(empId: String, empName: String) async throws -> Pairing {
        // Waits for the server on purpose: the phone can only use a code the server has.
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
    func cancelPairing(_ code: String) async throws {
        let b = db.batch(); b.deleteDocument(db.collection("pairings").document(code)); try await write(b)
    }
    func disconnect(_ d: Device) async throws {
        let batch = db.batch()
        batch.deleteDocument(doc("devices", d.id))
        if let k = d.keyId { batch.deleteDocument(doc("deviceKeys", k)) }   // so it cannot reconnect by itself
        try await write(batch)
    }
    func decide(_ r: ShiftRequest, approve: Bool, rate: Double) async throws {
        let reqRef = doc("requests", r.id)
        let batch = db.batch()
        guard approve else {
            batch.updateData(["status": "rejected", "decidedAt": FieldValue.serverTimestamp()], forDocument: reqRef)
            try await write(batch)
            return
        }
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
            let snap: DocumentSnapshot
            do { snap = try await doc("shifts", sid).getDocument() } catch { snap = try await doc("shifts", sid).getDocument(source: .cache) }
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
        try await write(batch)
    }
}

/// Firestore Timestamps (e.g. syncedAt written by the phone) -> ms numbers, so JSON decoding never drops a document.
func firestorePlain(_ v: Any) -> Any {
    switch v {
    case let t as Timestamp: return t.dateValue().timeIntervalSince1970 * 1000
    case let d as [String: Any]: return d.mapValues { firestorePlain($0) }
    case let a as [Any]: return a.map { firestorePlain($0) }
    case is NSNull, is String, is NSNumber: return v
    default: return NSNull()   // a type JSON can't hold (reference, geo point, bytes): read as "not set", never drop the doc
    }
}

/// Decodes a Firestore document's data the way FirestoreStore does (exposed for tests).
func decodeDoc<T: Decodable>(_ type: T.Type, id: String, _ data: [String: Any]) -> T? {
    var d = data.mapValues { firestorePlain($0) }; d["id"] = id
    guard JSONSerialization.isValidJSONObject(d), let json = try? JSONSerialization.data(withJSONObject: d) else { return nil }
    return try? JSONDecoder().decode(T.self, from: json)
}

/// "2026-11-05" + "08:14" in the Mac's time zone -> ms since 1970.
func localMillis(date: String, time: String) -> Double? {
    let d = date.split(separator: "-").compactMap { Int($0) }, t = time.split(separator: ":").compactMap { Int($0) }
    guard d.count == 3, t.count == 2 else { return nil }
    return gregorian.date(from: DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1]))
        .map { $0.timeIntervalSince1970 * 1000 }
}
