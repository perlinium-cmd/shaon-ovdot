import XCTest
import FirebaseFirestore
@testable import ShaonMac

/// The Mac side of the phone features, run on the in-memory store.
@MainActor
final class PhoneFlowTests: XCTestCase {
    private func model() -> (AppModel, DemoStore) {
        let store = DemoStore(seed: false)
        return (AppModel(store: store), store)
    }
    private func settle() async { await Task.yield(); await Task.yield() }

    func testPhoneShiftWithServerTimestampIsNotDropped() {
        // A phone shift as Firestore returns it: syncedAt is a Timestamp, not a number.
        let data: [String: Any] = ["empId": "e1", "date": "2026-11-05", "month": "2026-11", "in": "08:14", "out": "",
                                   "source": "phone", "open": true, "inAt": 1_793_888_040_000.0,
                                   "syncedAt": Timestamp(date: Date(timeIntervalSince1970: 1_793_888_041)), "deviceId": "ph"]
        let s = decodeDoc(Shift.self, id: "x", data)
        XCTAssertNotNil(s, "a phone shift must never disappear from the Mac")
        XCTAssertEqual(s?.isOpen, true)
        XCTAssertEqual(s?.syncedAt ?? 0, 1_793_888_041_000, accuracy: 1)
        XCTAssertEqual(s?.clockGapMinutes ?? 99, 1.0 / 60, accuracy: 0.01)
    }

    func testRunningShiftIsNeverMarkedPaid() async {
        let (m, store) = model()
        _ = try? await store.addEmployee(Employee(id: "", name: "נועה", rate: 40))
        let empId = m.employees!.first!.id
        let today = todayStr()
        let open = store.simulateClockIn(empId: empId, date: today, time: "08:00")
        let done = try! await store.addShift(Shift(empId: empId, date: today, month: String(today.prefix(7)), in: "06:00", out: "07:00", rate: 40))
        await settle()
        await m.markPaid([open, done])
        await settle()
        XCTAssertEqual(m.shifts?.first { $0.id == done }?.isPaid, true)
        XCTAssertEqual(m.shifts?.first { $0.id == open }?.isPaid, false)
    }

    func testApproveFixClosesShiftAndKeepsRate() async throws {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 40))
        let today = todayStr()
        let sid = store.simulateClockIn(empId: empId, date: today, time: "08:10")
        let rid = store.simulateRequest(ShiftRequest(empId: empId, type: "fix", shiftId: sid, date: today, in: "08:00", out: "14:30", status: "pending"))
        await settle()
        await m.decide(m.requests.first { $0.id == rid }!, approve: true)
        await settle()
        let s = try XCTUnwrap(m.shifts?.first { $0.id == sid })
        XCTAssertEqual(s.in, "08:00"); XCTAssertEqual(s.out, "14:30")
        XCTAssertFalse(s.isOpen)
        XCTAssertEqual(s.rate, 40)
        XCTAssertEqual(s.fixedBy, rid)
        XCTAssertEqual(m.pay(s), 6.5 * 40, accuracy: 0.001)
        XCTAssertTrue(m.pendingRequests.isEmpty)
    }

    func testApproveAddCreatesShift() async throws {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: nil))
        await m.saveSettings { $0.defaultRate = 42 }
        let today = todayStr()
        let rid = store.simulateRequest(ShiftRequest(empId: empId, type: "add", date: today, in: "09:00", out: "12:00", note: "שכחתי", status: "pending"))
        await settle()
        await m.decide(m.requests.first { $0.id == rid }!, approve: true)
        await settle()
        let s = try XCTUnwrap(m.shifts?.first { $0.requestId == rid })
        XCTAssertEqual(s.rate, 42)
        XCTAssertEqual(m.pay(s), 126, accuracy: 0.001)
    }

    func testRejectChangesNothing() async throws {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 40))
        let today = todayStr()
        let sid = try await store.addShift(Shift(empId: empId, date: today, month: String(today.prefix(7)), in: "08:00", out: "12:00", rate: 40))
        let rid = store.simulateRequest(ShiftRequest(empId: empId, type: "fix", shiftId: sid, date: today, in: "07:00", out: "12:00", status: "pending"))
        await settle()
        await m.decide(m.requests.first { $0.id == rid }!, approve: false)
        await settle()
        XCTAssertEqual(m.shifts?.first { $0.id == sid }?.in, "08:00")
        XCTAssertEqual(m.requests.first { $0.id == rid }?.status, "rejected")
    }

    func testCannotApproveFixOfPaidShift() async throws {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 40))
        let today = todayStr()
        let sid = try await store.addShift(Shift(empId: empId, date: today, month: String(today.prefix(7)), in: "08:00", out: "12:00", rate: 40, paid: true))
        let rid = store.simulateRequest(ShiftRequest(empId: empId, type: "fix", shiftId: sid, date: today, in: "07:00", out: "12:00", status: "pending"))
        await settle()
        await m.decide(m.requests.first { $0.id == rid }!, approve: true)
        await settle()
        XCTAssertEqual(m.shifts?.first { $0.id == sid }?.in, "08:00", "a paid shift must not change")
        XCTAssertTrue(m.requests.first { $0.id == rid }!.isPending)
    }

    func testRateChangeKeepsOldRateOnPastPhoneShifts() async throws {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 40))
        let today = todayStr()
        let sid = store.simulateClockIn(empId: empId, date: today, time: "08:00")
        store.simulateClockOut(sid, time: "12:00")
        await settle()
        var e = m.emp(empId)!; e.rate = 50
        await m.updateEmployee(e)
        await settle()
        let s = try XCTUnwrap(m.shifts?.first { $0.id == sid })
        XCTAssertEqual(s.rate, 40)
        XCTAssertEqual(m.pay(s), 160, accuracy: 0.001)
    }

    func testDefaultRateChangeKeepsOldRateOnPastPhoneShifts() async throws {
        let (m, store) = model()
        await m.saveSettings { $0.defaultRate = 40 }
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: nil))
        let today = todayStr()
        let sid = store.simulateClockIn(empId: empId, date: today, time: "08:00")
        store.simulateClockOut(sid, time: "10:00")
        await settle()
        await m.saveSettings { $0.defaultRate = 45 }
        await settle()
        XCTAssertEqual(m.shifts?.first { $0.id == sid }?.rate, 40)
    }

    // MARK: saved on the phone without approval (the manager only gets a notice)

    func testNoticeWithServerTimestampIsNotDropped() {
        let data: [String: Any] = ["empId": "e1", "type": "fix", "shiftId": "s1", "date": "2026-11-05", "in": "07:40", "out": "",
                                   "prevIn": "08:10", "prevOut": "", "deviceId": "ph",
                                   "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_793_888_041))]
        let n = decodeDoc(Notice.self, id: "n", data)
        XCTAssertNotNil(n, "a notice must never disappear from the Mac")
        XCTAssertEqual(n?.createdAt ?? 0, 1_793_888_041_000, accuracy: 1)
        XCTAssertEqual(n?.isSeen, false)
        XCTAssertEqual(n?.movedIn, true)
        XCTAssertEqual(n?.closedShift, false)
    }

    func testTypedInShiftCountsAndShowsAsNewUntilSeen() async throws {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 40))
        let today = todayStr()
        let sid = store.simulateManualShift(empId: empId, date: today, in: "07:00", out: "11:30")
        await settle()
        let s = try XCTUnwrap(m.shifts?.first { $0.id == sid })
        XCTAssertEqual(m.pay(s), 4.5 * 40, accuracy: 0.001, "a typed-in shift is paid like any other")
        XCTAssertNil(s.clockGapMinutes, "typed-in times are not a clock problem")
        XCTAssertEqual(m.unseenNotices.count, 1)
        XCTAssertEqual(m.describe(m.notices[0]).title, "נועה הזינה שעות")
        XCTAssertTrue(m.describe(m.notices[0]).detail.contains("4:30"))
        await m.markNoticesSeen()
        await settle()
        XCTAssertTrue(m.unseenNotices.isEmpty)
        XCTAssertEqual(m.notices.count, 1, "seen updates stay on the list")
    }

    func testSameDayChangesDescribeWhatChanged() async throws {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 40))
        let today = todayStr()
        // Still at work, fixed the clock-in.
        let open = store.simulateClockIn(empId: empId, date: today, time: "08:10")
        store.simulateFix(open, in: "07:50", out: "")
        await settle()
        var d = m.describe(m.notices[0])
        XCTAssertEqual(d.title, "נועה שינתה שעת כניסה")
        XCTAssertTrue(d.detail.contains("כניסה 07:50 במקום 08:10"), d.detail)
        XCTAssertEqual(m.openShift(of: empId)?.in, "07:50")
        XCTAssertNil(m.openShift(of: empId)?.clockGapMinutes)
        // Forgot to clock out: records when she really left (her 2nd change of this shift).
        try await Task.sleep(for: .milliseconds(5))
        store.simulateFix(open, in: "07:50", out: "12:00")
        await settle()
        d = m.describe(m.notices[0])
        XCTAssertEqual(d.title, "נועה רשמה שעת יציאה")
        XCTAssertTrue(d.detail.contains("07:50–12:00"), d.detail)
        XCTAssertTrue(d.detail.contains("שינוי שני"), d.detail)
        XCTAssertNil(m.openShift(of: empId))
        // A finished shift, exit moved later: says what changed and the total before and after.
        let done = store.simulateClockIn(empId: empId, date: today, time: "13:00")
        store.simulateClockOut(done, time: "17:00")
        try await Task.sleep(for: .milliseconds(5))
        store.simulateFix(done, in: "13:00", out: "17:30")
        await settle()
        d = m.describe(m.notices[0])
        XCTAssertEqual(d.title, "נועה שינתה שעות")
        XCTAssertTrue(d.detail.contains("יציאה 17:30 במקום 17:00"), d.detail)
        XCTAssertTrue(d.detail.contains("סה״כ 4:30 שעות במקום 4:00"), d.detail)
        XCTAssertFalse(d.detail.contains("כניסה"), d.detail)
        XCTAssertFalse(d.detail.contains("שינוי שני"), d.detail)
        XCTAssertEqual(m.shifts?.first { $0.id == done }?.edits, 1)
        XCTAssertEqual(m.unseenNotices.count, 3)
    }

    func testDeletingEmployeeRemovesHerNotices() async throws {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 40))
        _ = store.simulateManualShift(empId: empId, date: todayStr(), in: "07:00", out: "09:00")
        await settle()
        await m.deleteEmployee(m.emp(empId)!)
        await settle()
        XCTAssertTrue(m.notices.isEmpty)
    }

    func testPairingCodes() {
        let codes = (0..<500).map { _ in newPairingCode() }
        XCTAssertEqual(Set(codes).count, 500)
        for c in codes { XCTAssertTrue(c.range(of: "^[A-HJ-NP-Z2-9]{8}$", options: .regularExpression) != nil, c) }
    }

    // MARK: payments: the records always match the shifts

    private func paidSetup() async throws -> (AppModel, DemoStore, String, [String]) {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 37.5))
        let today = todayStr(), month = String(today.prefix(7))
        var ids: [String] = []
        for d in 1...3 {
            ids.append(try await store.addShift(Shift(empId: empId, date: "\(month)-0\(d)", month: month, in: "08:07", out: "13:52", rate: 37.5)))
        }
        m.month = month
        await settle()
        return (m, store, empId, ids)
    }

    func testPaymentRecordIsTheExactSumAndUnpayKeepsItExact() async throws {
        let (m, store, empId, ids) = try await paidSetup()
        await m.markPaid(ids)
        await settle()
        XCTAssertEqual(store.payments.count, 1)
        let p = try XCTUnwrap(store.payments.values.first)
        XCTAssertEqual(p.empId, empId)
        XCTAssertEqual(p.amount, 646.89)               // 3 × 215.63, to the agora
        XCTAssertEqual(Set(p.shiftIds ?? []), Set(ids))
        XCTAssertTrue(ids.allSatisfy { id in m.shifts?.first { $0.id == id }?.paymentId == p.id })
        // Taking one shift out leaves exactly the other two.
        await m.markUnpaid([ids[0]])
        await settle()
        let left = try XCTUnwrap(store.payments[p.id])
        XCTAssertEqual(left.amount, 431.26)
        XCTAssertEqual(Set(left.shiftIds ?? []), Set(ids[1...]))
        XCTAssertNil(m.shifts?.first { $0.id == ids[0] }?.paymentId)
        // The last ones out: the record goes away.
        await m.markUnpaid(Array(ids[1...]))
        await settle()
        XCTAssertTrue(store.payments.isEmpty)
        XCTAssertTrue(m.shifts!.allSatisfy { !$0.isPaid })
    }

    func testPayingTwiceNeverCreatesTwoPayments() async throws {
        let (m, store, _, ids) = try await paidSetup()
        // Two clicks at once: the second one starts while the first is still saving.
        let first = Task { await m.markPaid(ids) }
        let second = Task { await m.markPaid(ids) }
        await first.value; await second.value
        await m.markPaid(ids)   // already paid: nothing happens
        await settle()
        XCTAssertEqual(store.payments.count, 1)
        XCTAssertEqual(store.payments.values.first?.amount, 646.89)
    }

    func testDeletingAPaidShiftTakesItOutOfItsPayment() async throws {
        let (m, store, _, ids) = try await paidSetup()
        await m.markPaid(ids)
        await settle()
        await m.deleteShifts([ids[2]])
        await settle()
        XCTAssertEqual(store.payments.values.first?.amount, 431.26)
        XCTAssertEqual(Set(store.payments.values.first?.shiftIds ?? []), Set(ids[0...1]))
        XCTAssertNil(m.shifts?.first { $0.id == ids[2] })
    }

    func testUndoPutsPaymentAndShiftsBackExactly() async throws {
        let (m, store, _, ids) = try await paidSetup()
        let undo = UndoManager(); undo.groupsByEvent = false
        m.undoManager = undo
        undo.beginUndoGrouping()
        await m.markPaid(ids)
        undo.endUndoGrouping()
        await settle()
        XCTAssertEqual(store.payments.count, 1)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        // The redo that the undo registers afterwards needs the app's event loop (which opens undo groups by
        // itself); this test has none, so stop there — what's checked is that the undo puts everything back.
        m.undoManager = nil
        for _ in 0..<50 where !store.payments.isEmpty { await Task.yield(); try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(store.payments.isEmpty, "undo removes the payment it created")
        XCTAssertTrue(m.shifts!.allSatisfy { !$0.isPaid && $0.paymentId == nil })
    }

    func testPaidShiftHoursCannotChangeButOthersCan() async throws {
        let (m, _, _, ids) = try await paidSetup()
        await m.markPaid([ids[0]])
        await settle()
        var paid = try XCTUnwrap(m.shifts?.first { $0.id == ids[0] })
        paid.out = "15:00"
        let saved = await m.updateShift(paid)
        await settle()
        XCTAssertFalse(saved)
        XCTAssertEqual(m.shifts?.first { $0.id == ids[0] }?.out, "13:52", "what was paid stays what it was")
        var other = try XCTUnwrap(m.shifts?.first { $0.id == ids[1] })
        other.out = "15:00"
        let ok = await m.updateShift(other)
        await settle()
        XCTAssertTrue(ok)
        let after = try XCTUnwrap(m.shifts?.first { $0.id == ids[1] })
        XCTAssertEqual(after.out, "15:00")
        XCTAssertEqual(after.rate, 37.5, "editing times never touches the rate")
    }

    func testEditingTimesDoesNotOverwriteAPaymentMadeMeanwhile() async throws {
        let (m, store, _, ids) = try await paidSetup()
        var stale = try XCTUnwrap(m.shifts?.first { $0.id == ids[1] })   // the form was opened…
        await m.markPaid([ids[1]])                                       // …then it was paid (e.g. on the website)…
        await settle()
        stale.note = "x"                                                 // …and the form saved with unchanged times
        let ok = await m.updateShift(stale)
        await settle()
        XCTAssertTrue(ok)
        let s = try XCTUnwrap(m.shifts?.first { $0.id == ids[1] })
        XCTAssertTrue(s.isPaid, "the payment made meanwhile is kept")
        XCTAssertEqual(s.paymentId, store.payments.keys.first)
    }

    func testRateChangeWithoutInternetChangesNothing() async throws {
        let (m, store) = model()
        let empId = try await store.addEmployee(Employee(id: "", name: "נועה", rate: 40))
        let today = todayStr()
        let sid = store.simulateClockIn(empId: empId, date: today, time: "08:00")
        store.simulateClockOut(sid, time: "12:00")
        await settle()
        store.offline = true
        var e = m.emp(empId)!; e.rate = 50
        let saved = await m.updateEmployee(e)
        await settle()
        XCTAssertFalse(saved)
        XCTAssertEqual(m.emp(empId)?.rate, 40, "nothing changes when the old rate can't be locked onto every past shift")
        XCTAssertEqual(m.pay(try XCTUnwrap(m.shifts?.first { $0.id == sid })), 160)
        XCTAssertNotNil(m.toast)
    }

    func testAShiftWithAnOddFieldIsNeverDropped() {
        let data: [String: Any] = ["empId": "e1", "date": "2026-11-05", "month": "2026-11", "in": "08:00", "out": "16:00",
                                   "rate": "40", "paid": "yes", "special": ["rate": "x"], "edits": 1.5]
        let s = decodeDoc(Shift.self, id: "x", data)
        XCTAssertNotNil(s, "a shift with an odd field must still show (with that field as not set)")
        XCTAssertNil(s?.rate)
        XCTAssertEqual(shiftPay(s!, Employee(id: "e1", name: "a", rate: 45), defaultRate: 40), 360)
    }
}
