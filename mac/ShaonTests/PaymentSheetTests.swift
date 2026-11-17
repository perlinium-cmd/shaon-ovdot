import XCTest
@testable import ShaonMac

/// The payments list (edit / delete a payment) and "update this month's shifts too" after a rate change —
/// the same rules as the website, run on the in-memory store.
@MainActor
final class PaymentSheetTests: XCTestCase {
    private func settle() async { await Task.yield(); await Task.yield() }

    /// One employee at 37.50 with three unpaid 5:45 shifts this month (215.63 each).
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

    func testDeletingAPaymentUnmarksItsShifts() async throws {
        let (m, store, _, ids) = try await setup()
        await m.markPaid(ids)
        await settle()
        let p = try XCTUnwrap(store.payments.values.first)
        await m.deletePayment(p)
        await settle()
        XCTAssertTrue(store.payments.isEmpty)
        XCTAssertTrue(m.shifts!.allSatisfy { !$0.isPaid && $0.paymentId == nil && $0.paidAt == nil })
    }

    func testDeletingAPaymentNeverTouchesAShiftPaidByAnotherPayment() async throws {
        let (m, store, _, ids) = try await setup()
        await m.markPaid([ids[0]])
        await m.markPaid([ids[1]])
        await settle()
        let first = try XCTUnwrap(store.payments.values.first { $0.shiftIds == [ids[0]] })
        let second = try XCTUnwrap(store.payments.values.first { $0.shiftIds == [ids[1]] })
        // An old record that still lists ids[1], which has since been paid by `second`.
        var stale = first; stale.shiftIds = [ids[0], ids[1]]
        await m.deletePayment(stale)
        await settle()
        XCTAssertNil(store.payments[first.id])
        XCTAssertNotNil(store.payments[second.id])
        XCTAssertEqual(m.shifts?.first { $0.id == ids[0] }?.isPaid, false)
        XCTAssertEqual(m.shifts?.first { $0.id == ids[1] }?.paymentId, second.id, "a shift of another payment stays paid")
    }

    func testUndoBringsADeletedPaymentBackExactly() async throws {
        let (m, store, _, ids) = try await setup()
        await m.markPaid(ids)
        await settle()
        let p = try XCTUnwrap(store.payments.values.first)
        let undo = UndoManager(); undo.groupsByEvent = false
        m.undoManager = undo
        undo.beginUndoGrouping()
        await m.deletePayment(p)
        undo.endUndoGrouping()
        await settle()
        XCTAssertTrue(store.payments.isEmpty)
        undo.undo()
        m.undoManager = nil   // see PhoneFlowTests.testUndoPutsPaymentAndShiftsBackExactly
        for _ in 0..<50 where store.payments.isEmpty { await Task.yield(); try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.payments[p.id], p)
        XCTAssertTrue(m.shifts!.allSatisfy { $0.isPaid && $0.paymentId == p.id })
    }

    func testEditingAPaymentChangesOnlyHowAndWhen() async throws {
        let (m, store, _, ids) = try await setup()
        await m.markPaid(ids, method: "מזומן", date: "\(currentMonth())-05")
        await settle()
        let p = try XCTUnwrap(store.payments.values.first)
        await m.updatePayment(p, method: "ביט", date: "\(currentMonth())-07")
        await settle()
        let after = try XCTUnwrap(store.payments[p.id])
        XCTAssertEqual(after.method, "ביט")
        XCTAssertEqual(after.date, "\(currentMonth())-07")
        XCTAssertEqual(after.amount, 646.89)
        XCTAssertEqual(after.shiftIds, p.shiftIds)
        XCTAssertTrue(m.shifts!.allSatisfy { $0.isPaid && $0.paymentId == p.id })
    }

    func testNewRateReachesOnlyUnpaidShifts() async throws {
        let (m, store, _, ids) = try await setup()
        await m.markPaid([ids[0]])
        await settle()
        await m.applyRate(40, to: m.shifts!)
        await settle()
        XCTAssertEqual(m.shifts?.first { $0.id == ids[0] }?.rate, 37.5, "what was paid stays what it was")
        XCTAssertEqual(m.shifts?.first { $0.id == ids[1] }?.rate, 40)
        XCTAssertEqual(m.shifts?.first { $0.id == ids[2] }?.rate, 40)
        XCTAssertEqual(store.payments.values.first?.amount, 215.63)
    }

    func testBestAmpmUsesTheWallClock() {
        // Same answers as before the pay code learned about clock changes.
        XCTAssertEqual(bestAmpm(start: "08:00", hour: 4, minute: 0), "PM")
        XCTAssertEqual(bestAmpm(start: "22:00", hour: 6, minute: 0), "AM")
    }
}
