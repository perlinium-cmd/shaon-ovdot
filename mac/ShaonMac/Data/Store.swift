import Foundation

/// Same shape as the JS data layer (public/data.js): live listeners + simple writes.
@MainActor
protocol DataStore: AnyObject {
    var isDemo: Bool { get }
    func watchSettings(_ cb: @escaping (AppSettings) -> Void) -> () -> Void
    func saveSettings(_ s: AppSettings) async throws
    func watchEmployees(_ cb: @escaping ([Employee]) -> Void) -> () -> Void
    func addEmployee(_ e: Employee) async throws -> String
    func updateEmployee(_ e: Employee) async throws
    func deleteEmployee(_ id: String) async throws
    func watchShifts(month: String, _ cb: @escaping ([Shift]) -> Void) -> () -> Void
    func addShift(_ s: Shift) async throws -> String
    func updateShift(_ s: Shift) async throws
    func restoreShifts(_ s: [Shift]) async throws
    func deleteShifts(_ ids: [String]) async throws
    func setPaid(_ ids: [String], paid: Bool) async throws
}
