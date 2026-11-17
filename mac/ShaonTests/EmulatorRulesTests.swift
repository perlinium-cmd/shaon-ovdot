import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
@testable import ShaonMac

/// The Mac's real write path (FirestoreStore) against the local Firestore and Auth emulators with the repo's
/// firestore.rules: every delete the Mac makes must be accepted, each with an exact copy in the recycle bin.
/// Runs only from tools/emulator-test.sh (SHAON_EMULATOR=1); skipped everywhere else.
/// It uses its own Firebase apps on a "demo-" project, which has no real server: nothing here can reach the real data.
@MainActor
final class EmulatorRulesTests: XCTestCase {
    private struct Client { let db: Firestore; let uid: String }
    private static var clients: (mac: Client, web: Client)?

    /// Two clients signed in as the same manager: `mac` (the store under test; its cache keeps documents nobody listens
    /// to, like the Mac's disk cache) and `web` (another device that changes things meanwhile).
    private func connect() async throws -> (mac: Client, web: Client) {
        let env = ProcessInfo.processInfo.environment
        guard env["SHAON_EMULATOR"] == "1" else { throw XCTSkip("Runs only against the emulators (tools/emulator-test.sh)") }
        if let c = Self.clients { return c }
        let fsPort = env["SHAON_FIRESTORE_PORT"] ?? "8181", authPort = Int(env["SHAON_AUTH_PORT"] ?? "") ?? 9099
        let email = "mac-\(UUID().uuidString.prefix(8).lowercased())@example.test", password = "emulator-only"
        func client(_ name: String, keepsOldCopies: Bool) async throws -> Client {
            let o = FirebaseOptions(googleAppID: "1:123456789000:ios:0123456789abcdef", gcmSenderID: "123456789000")
            o.projectID = "demo-shaon"
            o.apiKey = "AIza" + String(repeating: "0", count: 35)
            FirebaseApp.configure(name: name, options: o)
            let app = try XCTUnwrap(FirebaseApp.app(name: name))
            let auth = Auth.auth(app: app)
            auth.useEmulator(withHost: "127.0.0.1", port: authPort)
            let db = Firestore.firestore(app: app)
            let s = db.settings
            s.host = "127.0.0.1:\(fsPort)"; s.isSSLEnabled = false
            s.cacheSettings = keepsOldCopies ? MemoryCacheSettings(garbageCollectorSettings: MemoryLRUGCSettings()) : MemoryCacheSettings()
            db.settings = s
            let r: AuthDataResult
            if keepsOldCopies { r = try await auth.createUser(withEmail: email, password: password) }
            else { r = try await auth.signIn(withEmail: email, password: password) }
            return Client(db: db, uid: r.user.uid)
        }
        let mac = try await client("emulatorMac", keepsOldCopies: true)    // signs up
        let web = try await client("emulatorWeb", keepsOldCopies: false)   // signs in as the same manager
        Self.clients = (mac, web)
        return (mac, web)
    }

    nonisolated override class func tearDown() {
        for n in ["emulatorMac", "emulatorWeb"] { if let a = FirebaseApp.app(name: n) { try? Auth.auth(app: a).signOut() } }
        super.tearDown()
    }

    // MARK: helpers
    private func ref(_ c: Client, _ col: String, _ id: String) -> DocumentReference {
        c.db.collection("users").document(c.uid).collection(col).document(id)
    }
    /// The document as the server has it now (nil: it does not exist).
    private func server(_ c: Client, _ col: String, _ id: String) async throws -> [String: Any]? {
        let s = try await ref(c, col, id).getDocument(source: .server)
        return s.exists ? s.data() : nil
    }
    private func seed(_ c: Client, _ docs: [(col: String, id: String, data: [String: Any])]) async throws {
        let b = c.db.batch()
        for d in docs { b.setData(d.data, forDocument: ref(c, d.col, d.id)) }
        try await b.commit()
    }
    private final class Problems { var list: [String] = [] }
    private func makeStore(_ c: Client) -> (FirestoreStore, Problems) {
        let s = FirestoreStore(uid: c.uid, db: c.db), p = Problems()
        s.onProblem = { p.list.append($0) }
        s.onDenied = { p.list.append("denied") }
        return (s, p)
    }
    /// Gone from its collection, and in the bin exactly as it was.
    private func assertInBin(_ c: Client, _ col: String, _ id: String, was: [String: Any]?,
                             file: StaticString = #filePath, line: UInt = #line) async throws {
        let live = try await server(c, col, id)
        XCTAssertNil(live, "\(col)/\(id) is still there", file: file, line: line)
        let t = try await server(c, "trash", Trash.id(col, id))
        XCTAssertNotNil(t, "\(col)/\(id) has no copy in the bin", file: file, line: line)
        XCTAssertEqual(t?["col"] as? String, col, file: file, line: line)
        XCTAssertEqual(t?["id"] as? String, id, file: file, line: line)
        XCTAssertEqual(t?["by"] as? String, c.uid, file: file, line: line)
        XCTAssertTrue(t?["deletedAt"] is Timestamp, file: file, line: line)
        XCTAssertNotNil(was, file: file, line: line)
        XCTAssertTrue(same(t?["data"], was), "the copy of \(col)/\(id) is not exact:\n\(String(describing: t?["data"]))\n\(String(describing: was))",
                      file: file, line: line)
    }

    private let ts = Timestamp(seconds: 1_762_408_681, nanoseconds: 123_456_000)
    /// A shift typed on the Mac or the website.
    private func handShift(_ emp: String, paidBy: String? = nil) -> [String: Any] {
        ["empId": emp, "date": "2026-11-05", "month": "2026-11", "in": "08:00", "out": "16:30", "rate": 38.25,
         "special": ["rate": 45.55, "hours": 2] as [String: Any], "paid": paidBy != nil,
         "paidAt": paidBy == nil ? NSNull() as Any : 1_763_370_000_000.0 as Any, "paymentId": paidBy.map { $0 as Any } ?? (NSNull() as Any),
         "note": NSNull(), "createdAt": 1_762_329_600_000]
    }
    /// A shift clocked on the phone (server timestamps, phone clock in ms, edits).
    private func phoneShift(_ emp: String) -> [String: Any] {
        ["empId": emp, "date": "2026-11-06", "month": "2026-11", "in": "07:58", "out": "15:02",
         "inAt": 1_762_408_680_000.0, "outAt": 1_762_434_120_000, "syncedAt": ts, "outSyncedAt": ts,
         "source": "phone", "open": false, "deviceId": "dev-1", "edited": true, "edits": 1, "noticeId": "n-1"]
    }
    private func payment(_ emp: String, _ shifts: [String], _ amount: Double) -> [String: Any] {
        ["empId": emp, "date": "2026-11-17", "amount": amount, "method": "מזומן", "shiftIds": shifts, "createdAt": 1_763_370_000_000]
    }

    // MARK: tests

    /// Without this the other tests prove nothing: the rules really refuse a delete with no copy in the bin.
    func testTheRulesRefuseADeleteWithoutACopy() async throws {
        let (m, _) = try await connect()
        try await seed(m, [("shifts", "nocopy", handShift("e-0"))])
        do {
            let b = m.db.batch(); b.deleteDocument(ref(m, "shifts", "nocopy")); try await b.commit()
            XCTFail("a shift was deleted without a copy in the bin: these rules do not ask for one")
        } catch let e as NSError {
            XCTAssertEqual(e.code, FirestoreErrorCode.permissionDenied.rawValue, "\(e)")
        }
        let still = try await server(m, "shifts", "nocopy")
        XCTAssertNotNil(still)
    }

    /// deleteShifts (a paid shift leaves its payment), deletePayment, and a phone shift: the writes AppModel sends.
    func testShiftAndPaymentDeletes() async throws {
        let (m, _) = try await connect()
        try await seed(m, [("shifts", "s1-a", handShift("e-1", paidBy: "p1")), ("shifts", "s1-b", handShift("e-1", paidBy: "p1")),
                           ("shifts", "s1-c", phoneShift("e-1")), ("payments", "p1", payment("e-1", ["s1-a", "s1-b"], 646.89))])
        let (store, problems) = makeStore(m)
        _ = try await store.snapshot([("shifts", "s1-a"), ("shifts", "s1-b"), ("shifts", "s1-c")])   // in this Mac's copy
        let a = try await server(m, "shifts", "s1-a"), c = try await server(m, "shifts", "s1-c")
        try await store.commit([.update("payments", "p1", ["shiftIds": ["s1-b"], "amount": 323.45]), .delete("shifts", "s1-a")])
        let p = try await server(m, "payments", "p1")
        try await store.commit([.update("shifts", "s1-b", ["paid": false, "paidAt": NSNull(), "paymentId": NSNull()]),
                                .delete("payments", "p1")])
        try await store.commit([.delete("shifts", "s1-c")])
        try await m.db.waitForPendingWrites()
        XCTAssertEqual(problems.list, [])
        try await assertInBin(m, "shifts", "s1-a", was: a)
        try await assertInBin(m, "payments", "p1", was: p)
        try await assertInBin(m, "shifts", "s1-c", was: c)
        let b = try await server(m, "shifts", "s1-b")
        XCTAssertEqual(b?["paid"] as? Bool, false)
    }

    /// This Mac read the shift earlier, then it was changed on the website while nothing here listened to it (another
    /// month on screen). The bin must get the shift as it is now — an old copy is refused by the rules.
    func testAShiftChangedElsewhereGoesToTheBinAsItIsNow() async throws {
        let (m, w) = try await connect()
        try await seed(m, [("shifts", "s2", handShift("e-2"))])
        let (store, problems) = makeStore(m)
        _ = try await store.snapshot([("shifts", "s2")])   // now in this Mac's copy
        try await ref(w, "shifts", "s2").updateData(["out": "17:00", "rate": 40])
        let now = try await server(w, "shifts", "s2")
        try await store.commit([.delete("shifts", "s2")])
        try await m.db.waitForPendingWrites()
        XCTAssertEqual(problems.list, [])
        try await assertInBin(m, "shifts", "s2", was: now)
    }

    /// deleteEmployee: her shifts, payments and the employee go to the bin (more than 5, so several batches);
    /// her phones, keys, requests and notices are deleted with no copy; another employee's shift stays.
    func testDeletingAnEmployeeWithEverything() async throws {
        let (m, _) = try await connect()
        let e = "e-3"
        var docs: [(col: String, id: String, data: [String: Any])] = [
            ("employees", e, ["name": "בדיקה", "rate": 38.25, "active": true, "createdAt": 1_762_329_600_000.0]),
            ("payments", "p3-a", payment(e, ["s3-1"], 323.45)), ("payments", "p3-b", payment(e, [], 0)),
            ("requests", "r3", ["empId": e, "type": "add", "date": "2026-11-10", "in": "08:00", "out": "12:00",
                                "status": "pending", "createdAt": ts, "deviceId": "d3-1"]),
            ("notices", "n3", ["empId": e, "type": "manual", "shiftId": "s3-2", "date": "2026-11-06", "in": "07:58",
                               "out": "15:02", "createdAt": ts, "deviceId": "d3-1"]),
        ]
        for i in 1...7 { docs.append(("shifts", "s3-\(i)", i % 2 == 0 ? phoneShift(e) : handShift(e, paidBy: i == 1 ? "p3-a" : nil))) }
        for i in 1...2 {
            docs.append(("devices", "d3-\(i)", ["empId": e, "keyId": "k3-\(i)", "model": "Pixel 8", "pairCode": "ABCD123\(i)", "pairedAt": ts]))
            docs.append(("deviceKeys", "k3-\(i)", ["empId": e, "deviceId": "d3-\(i)", "createdAt": ts]))
        }
        try await seed(m, docs + [("shifts", "s3-other", handShift("e-other"))])
        var before: [String: [String: Any]] = [:]
        for d in docs { before["\(d.col)/\(d.id)"] = try await server(m, d.col, d.id) }
        let (store, problems) = makeStore(m)
        try await store.deleteEmployee(e)
        try await m.db.waitForPendingWrites()
        XCTAssertEqual(problems.list, [])
        for d in docs {
            if Trash.cols.contains(d.col) { try await assertInBin(m, d.col, d.id, was: before["\(d.col)/\(d.id)"]) }
            else {
                let live = try await server(m, d.col, d.id), copy = try await server(m, "trash", Trash.id(d.col, d.id))
                XCTAssertNil(live, "\(d.col)/\(d.id)"); XCTAssertNil(copy, "\(d.col)/\(d.id)")
            }
        }
        let other = try await server(m, "shifts", "s3-other")
        XCTAssertNotNil(other)
    }

    /// ⌘Z of "mark paid" deletes the payment record it made; delete → ⌘Z → ⇧⌘Z deletes a shift a second time
    /// (its new copy replaces the old one in the bin).
    func testUndoAndRedo() async throws {
        let (m, _) = try await connect()
        let (store, problems) = makeStore(m)
        try await store.commit([.set("payments", "p4", payment("e-4", ["s4"], 100))])
        try await m.db.waitForPendingWrites()
        let p = try await server(m, "payments", "p4")
        try await store.restore([DocSnapshot(col: "payments", id: "p4", data: nil)])

        try await seed(m, [("shifts", "s4", handShift("e-4"))])
        let before = try await store.snapshot([("shifts", "s4")])
        try await store.commit([.delete("shifts", "s4")])
        try await store.restore(before)                                            // ⌘Z
        try await store.restore([DocSnapshot(col: "shifts", id: "s4", data: nil)])  // ⇧⌘Z
        try await m.db.waitForPendingWrites()
        XCTAssertEqual(problems.list, [])
        try await assertInBin(m, "payments", "p4", was: p)
        try await assertInBin(m, "shifts", "s4", was: before.first?.data)
    }

    func testDeletingWhatIsAlreadyGoneNeedsNoCopy() async throws {
        let (m, _) = try await connect()
        let (store, problems) = makeStore(m)
        try await store.commit([.delete("shifts", "never-was"), .delete("employees", "never-was")])
        try await m.db.waitForPendingWrites()
        XCTAssertEqual(problems.list, [])
        let a = try await server(m, "trash", Trash.id("shifts", "never-was")), b = try await server(m, "trash", Trash.id("employees", "never-was"))
        XCTAssertNil(a); XCTAssertNil(b)
    }

    /// Every employee, shift and payment of a local backup of the real data (copied into the emulator only;
    /// tools/emulator-test.sh passes it in with SHAON_SEED_FILE): the Mac deletes each, and each copy is exact.
    func testEveryRecordOfARealBackup() async throws {
        let (m, _) = try await connect()
        guard let json = ProcessInfo.processInfo.environment["SHAON_SEED"], !json.isEmpty else { throw XCTSkip("no backup passed in") }
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        var docs: [(col: String, id: String, data: [String: Any])] = []
        for (path, v) in try XCTUnwrap(root["docs"] as? [String: Any]) {
            let p = path.split(separator: "/").map(String.init)
            guard p.count == 4, p[0] == "users", let fields = (v as? [String: Any])?["fields"] as? [String: Any] else { continue }
            docs.append((p[2], p[3], fields.mapValues(fromBackup)))
        }
        let records = docs.filter { Trash.cols.contains($0.col) }
        XCTAssertFalse(records.isEmpty)
        try await seed(m, docs)
        var before: [String: [String: Any]] = [:]
        for d in records { before["\(d.col)/\(d.id)"] = try await server(m, d.col, d.id) }
        let (store, problems) = makeStore(m)
        for d in docs where d.col == "employees" { try await store.deleteEmployee(d.id) }
        let left = records.filter { $0.col != "employees" }.map { DocWrite.delete($0.col, $0.id) }   // of no employee
        try await store.commit(left)
        try await m.db.waitForPendingWrites()
        XCTAssertEqual(problems.list, [])
        for d in records { try await assertInBin(m, d.col, d.id, was: before["\(d.col)/\(d.id)"]) }
    }

    /// A value of the backup file (Firestore's REST format), as the SDK hands it over.
    private func fromBackup(_ v: Any) -> Any {
        guard let t = v as? [String: Any], let f = t.first else { return NSNull() }
        switch f.key {
        case "stringValue": return f.value as? String ?? ""
        case "integerValue": return NSNumber(value: Int64("\(f.value)") ?? 0)
        case "doubleValue": return NSNumber(value: (f.value as? NSNumber)?.doubleValue ?? Double("\(f.value)") ?? 0)
        case "booleanValue": return (f.value as? Bool) ?? false
        case "timestampValue":
            let s = f.value as? String ?? ""
            var base = s, nanos: Int32 = 0
            if let dot = s.firstIndex(of: "."), let z = s.lastIndex(of: "Z") {
                nanos = Int32((String(s[s.index(after: dot)..<z]) + "000000000").prefix(9)) ?? 0
                base = String(s[..<dot]) + "Z"
            }
            let d = ISO8601DateFormatter().date(from: base) ?? Date(timeIntervalSince1970: 0)
            return Timestamp(seconds: Int64(d.timeIntervalSince1970), nanoseconds: nanos)
        case "mapValue": return ((f.value as? [String: Any])?["fields"] as? [String: Any] ?? [:]).mapValues(fromBackup)
        case "arrayValue": return ((f.value as? [String: Any])?["values"] as? [Any] ?? []).map(fromBackup)
        default: return NSNull()
        }
    }
}

/// Equal, with every number of the same kind (whole, fraction, yes/no) — as Firestore keeps it.
private func same(_ a: Any?, _ b: Any?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    switch (a, b) {
    case let (x as [String: Any], y as [String: Any]): return x.count == y.count && x.allSatisfy { same($0.value, y[$0.key]) }
    case let (x as [Any], y as [Any]): return x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
    case let (x as String, y as String): return x == y
    case let (x as NSNumber, y as NSNumber): return String(cString: x.objCType) == String(cString: y.objCType) && x == y
    case let (x as Timestamp, y as Timestamp): return x == y
    case (is NSNull, is NSNull): return true
    default: return false
    }
}
