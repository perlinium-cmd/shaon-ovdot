import Foundation

/// In-memory store for previews, tests and running without Firebase.
@MainActor
final class DemoStore: DataStore {
    let isDemo = true
    private var settings = AppSettings(defaultRate: 40, timeFormat: "24")
    private var employees: [String: Employee] = [:]
    private var shifts: [String: Shift] = [:]
    private var devices: [String: Device] = [:]
    private var requests: [String: ShiftRequest] = [:]
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
        employees[id] = nil; shifts = shifts.filter { $0.value.empId != id }
        devices = devices.filter { $0.value.empId != id }; requests = requests.filter { $0.value.empId != id }; notify()
    }
    func watchShifts(month: String, _ cb: @escaping ([Shift]) -> Void) -> () -> Void {
        watch { [weak self] in if let s = self { cb(s.shifts.values.filter { $0.month == month }) } }
    }
    func addShift(_ s: Shift) async throws -> String { let id = newId(); var s = s; s.id = id; shifts[id] = s; notify(); return id }
    func updateShift(_ s: Shift) async throws { shifts[s.id] = s; notify() }
    func restoreShifts(_ list: [Shift]) async throws { list.forEach { shifts[$0.id] = $0 }; notify() }
    func deleteShifts(_ ids: [String]) async throws { ids.forEach { shifts[$0] = nil }; notify() }
    func setPaid(_ ids: [String], paid: Bool) async throws {
        for id in ids { shifts[id]?.paid = paid; shifts[id]?.paidAt = paid ? Date().timeIntervalSince1970 * 1000 : nil }
        notify()
    }

    func shiftsWithoutRate(empId: String) async throws -> [Shift] { shifts.values.filter { $0.empId == empId && $0.rate == nil } }
    func setRates(_ rates: [String: Double]) async throws { for (id, r) in rates { shifts[id]?.rate = r }; notify() }

    func watchOpenShifts(_ cb: @escaping ([Shift]) -> Void) -> () -> Void { watch { [weak self] in if let s = self { cb(s.shifts.values.filter(\.isOpen)) } } }
    func watchDevices(_ cb: @escaping ([Device]) -> Void) -> () -> Void { watch { [weak self] in if let s = self { cb(Array(s.devices.values)) } } }
    func watchRequests(_ cb: @escaping ([ShiftRequest]) -> Void) -> () -> Void { watch { [weak self] in if let s = self { cb(Array(s.requests.values)) } } }
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
