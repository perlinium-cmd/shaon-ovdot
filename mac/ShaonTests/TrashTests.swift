import XCTest
@testable import ShaonMac

/// Recycle bin: deleted employees, shifts and payments keep an exact copy (same rules as public/trash.js).
@MainActor
final class TrashTests: XCTestCase {
    private func settle() async { await Task.yield(); await Task.yield() }

    // MARK: batches (same cut as the website, so the server rules see the same thing from every app)

    func testAtMostFiveCopiesPerBatch() {
        XCTAssertEqual(Trash.plan(Array(repeating: true, count: 12)).map(\.count), [5, 5, 2])
    }
    func testWritesWithoutCopiesStayTogetherUpTo450() {
        XCTAssertEqual(Trash.plan(Array(repeating: false, count: 900)).map(\.count), [450, 450])
        XCTAssertEqual(Trash.plan(Array(repeating: false, count: 3)), [[0, 1, 2]])
    }
    func testADeleteWithItsCopyIsNeverSplit() {
        // 449 updates + a delete with a copy = 451 writes: the delete and its copy go to the next batch together.
        XCTAssertEqual(Trash.plan(Array(repeating: false, count: 449) + [true]).map(\.count), [449, 1])
    }
    func testOrderIsKept() {
        let copies = [true, false, true, true, true, true, true, false]
        XCTAssertEqual(Trash.plan(copies), [[0, 1, 2, 3, 4, 5], [6, 7]])
        XCTAssertEqual(Trash.plan([]), [])
    }

    // MARK: what goes to the bin

    private func setup() async throws -> (AppModel, DemoStore, String, [String]) {
        let store = DemoStore(seed: false)
        let m = AppModel(store: store)
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 37.5))
        let month = currentMonth()
        var ids: [String] = []
        for d in 1...3 {
            ids.append(try await store.addShift(Shift(empId: empId, date: "\(month)-0\(d)", month: month, in: "08:07", out: "13:52", rate: 37.5)))
        }
        m.month = month
        await settle()
        return (m, store, empId, ids)
    }

    func testADeletedShiftIsKeptExactly() async throws {
        let (_, store, _, ids) = try await setup()
        let before = try await store.snapshot([("shifts", ids[0])]).first?.data
        try await store.commit([.delete("shifts", ids[0])])
        let copy = try XCTUnwrap(store.trash[Trash.id("shifts", ids[0])])
        XCTAssertEqual(copy["col"] as? String, "shifts")
        XCTAssertEqual(copy["id"] as? String, ids[0])
        XCTAssertEqual(copy["data"] as? NSDictionary, before as NSDictionary?)
        XCTAssertEqual(store.trash.count, 1)
    }

    func testOnlyDeletesGoToTheBin() async throws {
        let (m, store, _, ids) = try await setup()
        await m.markPaid(ids)            // updates shifts, creates a payment
        await m.applyRate(40, to: m.shifts!)
        await settle()
        XCTAssertTrue(store.trash.isEmpty)
    }

    func testADeletedPaymentIsKeptButItsShiftsAreOnlyUnmarked() async throws {
        let (m, store, _, ids) = try await setup()
        await m.markPaid(ids)
        await settle()
        let p = try XCTUnwrap(store.payments.values.first)
        await m.deletePayment(p)
        await settle()
        XCTAssertEqual(Set(store.trash.keys), [Trash.id("payments", p.id)])
        let data = try XCTUnwrap(store.trash[Trash.id("payments", p.id)]?["data"] as? [String: Any])
        XCTAssertEqual(data["amount"] as? Double, 646.89)
        XCTAssertEqual(data["shiftIds"] as? [String], p.shiftIds)
    }

    func testADeletedEmployeeKeepsHerShiftsAndPayments() async throws {
        let (m, store, empId, ids) = try await setup()
        await m.markPaid([ids[0]])
        await settle()
        let p = try XCTUnwrap(store.payments.values.first)
        try await store.deleteEmployee(empId)
        let want: Set<String> = Set(ids.map { Trash.id("shifts", $0) } + [Trash.id("payments", p.id), Trash.id("employees", empId)])
        XCTAssertEqual(Set(store.trash.keys), want)
        XCTAssertEqual((store.trash[Trash.id("employees", empId)]?["data"] as? [String: Any])?["name"] as? String, "נועה")
    }

    func testDeletingSomethingAlreadyGoneLeavesNoCopy() async throws {
        let (_, store, _, _) = try await setup()
        try await store.commit([.delete("shifts", "nope")])
        XCTAssertTrue(store.trash.isEmpty)
    }
}
