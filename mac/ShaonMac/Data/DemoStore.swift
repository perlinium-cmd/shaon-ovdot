import Foundation

/// In-memory store for previews, tests and running without Firebase.
@MainActor
final class DemoStore: DataStore {
    let isDemo = true
    private var settings = AppSettings(defaultRate: 40, timeFormat: "24")
    private var employees: [String: Employee] = [:]
    private var shifts: [String: Shift] = [:]
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
    func deleteEmployee(_ id: String) async throws { employees[id] = nil; shifts = shifts.filter { $0.value.empId != id }; notify() }
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
}
