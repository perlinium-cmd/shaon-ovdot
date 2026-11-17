import Foundation

/// In-memory store for previews, tests and running without Firebase.
@MainActor
final class DemoStore: DataStore {
    let isDemo = true
    var onProblem: ((String) -> Void)?
    var onDenied: (() -> Void)?
    /// Tests: makes shiftsWithoutRate fail like the real store does without internet.
    var offline = false
    private var settings = AppSettings(defaultRate: 40, timeFormat: "24")
    private var employees: [String: Employee] = [:]
    private var shifts: [String: Shift] = [:]
    private(set) var payments: [String: Payment] = [:]
    private var devices: [String: Device] = [:]
    private var requests: [String: ShiftRequest] = [:]
    private var notices: [String: Notice] = [:]
    private var pairings: [String: (Pairing, used: Bool)] = [:]
    private var listeners: [UUID: () -> Void] = [:]

    init(seed: Bool = true) {
        guard seed else { return }
        let a = Employee(id: "a", name: "דנה", rate: nil, createdAt: 0)
        let b = Employee(id: "b", name: "מיכל", rate: 45, createdAt: 0)
        employees = ["a": a, "b": b]
        let m = String(ISO8601DateFormatter().string(from: .now).prefix(7))
        for d in 1...6 {
            let date = "\(m)-" + String(format: "%02d", d)
            let s = Shift(id: "s\(d)", empId: d % 2 == 0 ? "a" : "b", date: date, month: m, in: "08:00", out: d == 3 ? "17:30" : "16:00", rate: d % 2 == 0 ? 40 : 45)
            shifts[s.id] = s
        }
        // A connected phone, a running shift and a pending request, so the phone features show in the demo.
        let now = Date()
        let today = dateStr(now)
        let inAt = now.addingTimeInterval(-3 * 3600 - 42 * 60)
        let hm = { (d: Date) in String(format: "%02d:%02d", gregorian.component(.hour, from: d), gregorian.component(.minute, from: d)) }
        devices["ph1"] = Device(id: "ph1", empId: "a", model: "Galaxy A54", pairedAt: now.timeIntervalSince1970 * 1000 - 86_400_000, keyId: "k1")
        let ms = inAt.timeIntervalSince1970 * 1000
        shifts["live"] = Shift(id: "live", empId: "a", date: today, month: String(today.prefix(7)), in: hm(inAt), out: "",
                               source: "phone", open: true, inAt: ms, syncedAt: ms + 900, deviceId: "ph1")
        requests["r1"] = ShiftRequest(id: "r1", empId: "a", type: "fix", shiftId: "s2", date: shifts["s2"]!.date, in: "08:00", out: "16:30",
                                      note: "שכחתי ללחוץ יציאה", status: "pending", createdAt: now.timeIntervalSince1970 * 1000)
        // A shift she typed in herself after work (saved without approval, the manager only hears about it).
        let typedIn = Shift(id: "m1", empId: "b", date: today, month: String(today.prefix(7)), in: "07:30", out: "11:15",
                            source: "phone", open: false, manual: true)
        shifts[typedIn.id] = typedIn
        notices["n1"] = Notice(id: "n1", empId: "b", type: "manual", shiftId: "m1", date: today, in: "07:30", out: "11:15",
                               createdAt: now.timeIntervalSince1970 * 1000 - 20 * 60_000)
    }

    private func notify() { listeners.values.forEach { $0() } }
    private func watch(_ fn: @escaping () -> Void) -> () -> Void {
        let id = UUID(); listeners[id] = fn; fn()
        return { [weak self] in self?.listeners[id] = nil }
    }
    private func newId() -> String { String(UUID().uuidString.prefix(10)) }

    func watchSettings(_ cb: @escaping (AppSettings) -> Void) -> () -> Void { watch { [weak self] in if let s = self?.settings { cb(s) } } }
    func saveSettings(_ s: AppSettings) async throws { settings = s; notify() }
    func watchEmployees(_ cb: @escaping ([Employee]) -> Void) -> () -> Void { watch { [weak self] in if let s = self { cb(Array(s.employees.values)) } } }
    func addEmployee(_ e: Employee) async throws -> String { let id = newId(); var e = e; e.id = id; employees[id] = e; notify(); return id }
    func updateEmployee(_ e: Employee) async throws { employees[e.id] = e; notify() }
    func deleteEmployee(_ id: String) async throws {
        shifts.values.filter { $0.empId == id }.forEach { toTrash("shifts", $0.id) }
        payments.values.filter { $0.empId == id }.forEach { toTrash("payments", $0.id) }
        toTrash("employees", id)
        employees[id] = nil; shifts = shifts.filter { $0.value.empId != id }; payments = payments.filter { $0.value.empId != id }
        devices = devices.filter { $0.value.empId != id }; requests = requests.filter { $0.value.empId != id }
        notices = notices.filter { $0.value.empId != id }; notify()
    }
    func watchShifts(month: String, _ cb: @escaping ([Shift]) -> Void) -> () -> Void {
        watch { [weak self] in if let s = self { cb(s.shifts.values.filter { $0.month == month }) } }
    }
    func addShift(_ s: Shift) async throws -> String { let id = s.id.isEmpty ? newId() : s.id; var s = s; s.id = id; shifts[id] = s; notify(); return id }

    // MARK: batches + undo (documents as dictionaries, like Firestore)
    private func dict<T: Encodable>(_ v: T) -> [String: Any] {
        guard let json = try? JSONEncoder().encode(v), var d = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return [:] }
        d["id"] = nil
        return d
    }
    private func raw(_ col: String, _ id: String) -> [String: Any]? {
        switch col {
        case "shifts": shifts[id].map(dict)
        case "payments": payments[id].map(dict)
        case "employees": employees[id].map(dict)
        default: nil
        }
    }
    private func put(_ col: String, _ id: String, _ data: [String: Any]?) {
        switch col {
        case "shifts": shifts[id] = data.flatMap { decodeDoc(Shift.self, id: id, $0) }
        case "payments": payments[id] = data.flatMap { decodeDoc(Payment.self, id: id, $0) }
        case "employees": employees[id] = data.flatMap { decodeDoc(Employee.self, id: id, $0) }
        case "notices": if let d = data, d["seen"] as? Bool == true { notices[id]?.seen = true }
        default: break
        }
    }
    func newId(_ col: String) -> String { newId() }
    func commit(_ writes: [DocWrite]) async throws {
        // Like a Firestore batch: an update of a missing document fails all of it.
        for w in writes { if case let .update(c, id, _) = w, c != "notices", raw(c, id) == nil { throw StoreError.missingShift } }
        for w in writes {
            switch w {
            case let .set(c, id, data): put(c, id, data)
            case let .update(c, id, data): put(c, id, (raw(c, id) ?? [:]).merging(data) { $1 })
            case let .delete(c, id): toTrash(c, id); put(c, id, nil)
            }
        }
        notify()
    }
    /// Recycle bin, like users/{uid}/trash: "col__id" → {col, id, data, by}.
    private(set) var trash: [String: [String: Any]] = [:]
    private func toTrash(_ c: String, _ id: String) {
        guard Trash.cols.contains(c), let d = raw(c, id) else { return }
        trash[Trash.id(c, id)] = ["col": c, "id": id, "data": d, "by": "demo"]
    }
    func snapshot(_ refs: [(col: String, id: String)]) async throws -> [DocSnapshot] {
        refs.map { DocSnapshot(col: $0.col, id: $0.id, data: raw($0.col, $0.id)) }
    }

    func shiftsWithoutRate(empId: String) async throws -> [Shift] {
        if offline { throw StoreError.offline }
        return shifts.values.filter { $0.empId == empId && $0.rate == nil }
    }
    func setRates(_ rates: [String: Double]) async throws { for (id, r) in rates { shifts[id]?.rate = r }; notify() }
    func watchPayments(empId: String, _ cb: @escaping ([Payment]) -> Void) -> () -> Void {
        watch { [weak self] in if let s = self { cb(s.payments.values.filter { $0.empId == empId }) } }
    }

    func watchOpenShifts(_ cb: @escaping ([Shift]) -> Void) -> () -> Void { watch { [weak self] in if let s = self { cb(s.shifts.values.filter(\.isOpen)) } } }
    func watchDevices(_ cb: @escaping ([Device]) -> Void) -> () -> Void { watch { [weak self] in if let s = self { cb(Array(s.devices.values)) } } }
    func watchRequests(_ cb: @escaping ([ShiftRequest]) -> Void) -> () -> Void { watch { [weak self] in if let s = self { cb(Array(s.requests.values)) } } }
    func watchNotices(_ cb: @escaping ([Notice]) -> Void) -> () -> Void {
        watch { [weak self] in if let s = self { cb(s.notices.values.sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }) } }
    }
    func markNoticesSeen(_ ids: [String]) async throws { ids.forEach { notices[$0]?.seen = true }; notify() }
    func createPairing(empId: String, empName: String) async throws -> Pairing {
        let p = Pairing(code: newPairingCode(), empId: empId, empName: empName, expiresAt: Date().addingTimeInterval(600))
        pairings[p.code] = (p, false); notify(); return p
    }
    func watchPairing(_ code: String, _ cb: @escaping (Bool) -> Void) -> () -> Void { watch { [weak self] in cb(self?.pairings[code]?.used ?? false) } }
    func cancelPairing(_ code: String) async throws { pairings[code] = nil }
    func disconnect(_ d: Device) async throws { devices[d.id] = nil; notify() }
    /// Demo/tests: simulate a phone using a code.
    func simulatePhoneUses(_ code: String) {
        guard let p = pairings[code] else { return }
        pairings[code] = (p.0, true)
        devices[newId()] = Device(empId: p.0.empId, model: "Pixel 8", pairedAt: Date().timeIntervalSince1970 * 1000, keyId: newId())
        notify()
    }
    /// Demo/tests: simulate the phone's clock-in / clock-out / request.
    func simulateClockIn(empId: String, date: String, time: String) -> String {
        let id = newId(), ms = localMillis(date: date, time: time) ?? 0
        shifts[id] = Shift(id: id, empId: empId, date: date, month: String(date.prefix(7)), in: time, out: "", source: "phone", open: true, inAt: ms, syncedAt: ms)
        notify(); return id
    }
    func simulateClockOut(_ id: String, time: String) { shifts[id]?.out = time; shifts[id]?.open = false; notify() }
    func simulateRequest(_ r: ShiftRequest) -> String { let id = newId(); var r = r; r.id = id; requests[id] = r; notify(); return id }
    /// The phone typing in a forgotten shift on the same day: the shift and its notice arrive together.
    func simulateManualShift(empId: String, date: String, in tin: String, out tout: String) -> String {
        let id = newId(), nid = newId()
        shifts[id] = Shift(id: id, empId: empId, date: date, month: String(date.prefix(7)), in: tin, out: tout, source: "phone", open: false,
                           inAt: localMillis(date: date, time: tin), outAt: localMillis(date: date, time: tout), manual: true)
        notices[nid] = Notice(id: nid, empId: empId, type: "manual", shiftId: id, date: date, in: tin, out: tout, createdAt: Date().timeIntervalSince1970 * 1000)
        notify(); return id
    }
    /// The phone changing a clock-in / clock-out on the day (out "" = a running shift keeps running).
    func simulateFix(_ id: String, in tin: String, out tout: String) {
        guard var s = shifts[id] else { return }
        let nid = newId(), edit = (s.edits ?? 0) + 1
        notices[nid] = Notice(id: nid, empId: s.empId, type: "fix", shiftId: id, date: s.date, in: tin, out: tout, prevIn: s.in, prevOut: s.out,
                              edit: edit, createdAt: Date().timeIntervalSince1970 * 1000)
        s.in = tin; s.inAt = localMillis(date: s.date, time: tin); s.edited = true; s.edits = edit
        if !tout.isEmpty { s.out = tout; s.outAt = localMillis(date: s.date, time: tout); s.open = false }
        shifts[id] = s; notify()
    }

    func decide(_ r: ShiftRequest, approve: Bool, rate: Double) async throws {
        guard approve else { requests[r.id]?.status = "rejected"; notify(); return }
        if r.type == "add" {
            let id = newId()
            shifts[id] = Shift(id: id, empId: r.empId, date: r.date, month: String(r.date.prefix(7)), in: r.in, out: r.out, rate: rate, paid: false,
                               source: "request", requestId: r.id)
        } else {
            guard let sid = r.shiftId, var s = shifts[sid] else { throw StoreError.missingShift }
            if s.isPaid { throw StoreError.alreadyPaid }
            s.in = r.in; s.date = r.date; s.month = String(r.date.prefix(7)); s.fixedBy = r.id
            if s.rate == nil { s.rate = rate }
            if r.out.isEmpty { if s.isOpen { s.inAt = localMillis(date: r.date, time: r.in) } }
            else { s.out = r.out; s.open = false }
            shifts[sid] = s
        }
        requests[r.id]?.status = "approved"
        notify()
    }
}
