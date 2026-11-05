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

    // Rates: lock a rate onto shifts that have none yet (before a rate change).
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
