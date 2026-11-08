import XCTest
@testable import ShaonMac

final class PayTests: XCTestCase {
    func shift(_ i: String, _ o: String, rate: Double? = 40, special: Special? = nil) -> Shift {
        Shift(empId: "e", date: "2026-09-01", month: "2026-09", in: i, out: o, rate: rate, special: special)
    }

    func testMinutes() {
        XCTAssertEqual(shiftMinutes("2026-09-01", "08:00", "16:30"), 510)
        XCTAssertEqual(shiftMinutes("2026-09-01", "22:00", "06:00"), 480)   // overnight
        XCTAssertTrue(isOvernight("22:00", "06:00"))
        XCTAssertEqual(shiftMinutes("2026-09-01", "", "06:00"), 0)
        XCTAssertEqual(shiftMinutes("2026-10-24", "22:00", "06:00"), 540)   // the clock goes back that night
        XCTAssertEqual(shiftMinutes("2026-03-26", "22:00", "06:00"), 420)   // and forward that night
    }

    func testPayRegularAndSpecial() {
        XCTAssertEqual(shiftPay(shift("08:00", "16:00"), nil, defaultRate: 0), 320, accuracy: 0.001)
        let all = shift("08:00", "16:00", special: Special(rate: 60, hours: nil))
        XCTAssertEqual(shiftPay(all, nil, defaultRate: 0), 480, accuracy: 0.001)
        let part = shift("08:00", "16:00", special: Special(rate: 60, hours: 2))
        XCTAssertEqual(shiftPay(part, nil, defaultRate: 0), 6 * 40 + 2 * 60, accuracy: 0.001)
        let over = shift("08:00", "10:00", special: Special(rate: 60, hours: 5))   // capped at shift length
        XCTAssertEqual(shiftPay(over, nil, defaultRate: 0), 120, accuracy: 0.001)
    }

    func testRateFieldText() {
        XCTAssertEqual(fmtNum(45), "45")
        XCTAssertEqual(fmtNum(100), "100")
        XCTAssertEqual(fmtNum(0), "0")
        XCTAssertEqual(fmtNum(45.5), "45.5")
        XCTAssertEqual(fmtNum(45.25), "45.25")
        XCTAssertEqual(fmtNum(32.3), "32.3")
        // What the field shows reads back as exactly the same rate (no agora lost or added).
        for r in [0, 1, 29.99, 32.3, 40, 45.5, 45.25, 99_999.99] { XCTAssertEqual(parseRate(fmtNum(r)), r) }
    }

    func testRateFallback() {
        let s = shift("08:00", "09:00", rate: nil)
        XCTAssertEqual(shiftPay(s, Employee(id: "e", name: "a", rate: 50), defaultRate: 40), 50)
        XCTAssertEqual(shiftPay(s, Employee(id: "e", name: "a", rate: nil), defaultRate: 40), 40)
    }

    func testAggregate() {
        var paid = shift("08:00", "10:00"); paid.paid = true
        let a = aggregate([paid, shift("08:00", "09:00")], employees: [], defaultRate: 40)["e"]!
        XCTAssertEqual(a.minutes, 180)
        XCTAssertEqual(a.pay, 120, accuracy: 0.001)
        XCTAssertEqual(a.unpaid, 40, accuracy: 0.001)
    }

    func testTotalsAreExactSumsOfRows() {
        // 3 × 215.625 → each row 215.63, the total 646.89 (not round(646.875) = 646.88), paid + left = total.
        var list = (0..<3).map { i in Shift(id: "\(i)", empId: "e", date: "2026-09-0\(i + 1)", month: "2026-09", in: "08:07", out: "13:52", rate: 37.5) }
        list[0].paid = true
        let a = aggregate(list, employees: [], defaultRate: nil)["e"]!
        XCTAssertEqual(a.payAgorot, 3 * 21563)
        XCTAssertEqual(a.paidAgorot, 21563)
        XCTAssertEqual(a.unpaid, 431.26)
        XCTAssertEqual(fmtMoney(a.pay), fmtMoney(646.89))
        XCTAssertEqual(a.unpaidShifts.count, 2)
        XCTAssertFalse(a.allPaid)
    }

    func testOnlyRunningShiftIsNotPaid() {
        let running = Shift(empId: "e", date: "2026-09-01", month: "2026-09", in: "08:00", out: "", rate: 40, open: true)
        let a = aggregate([running], employees: [], defaultRate: nil)["e"]!
        XCTAssertFalse(a.allPaid, "a running shift alone must not read as paid")
        XCTAssertTrue(a.unpaidShifts.isEmpty)
    }

    func testParseTyped() {
        XCTAssertEqual(parseTyped("830"), "08:30")
        XCTAssertEqual(parseTyped("0830"), "08:30")
        XCTAssertEqual(parseTyped("8:30"), "08:30")
        XCTAssertEqual(parseTyped("2359"), "23:59")
        XCTAssertEqual(parseTyped("8"), "08:00")
        XCTAssertEqual(parseTyped(""), "")
        XCTAssertNil(parseTyped("2460"))
        XCTAssertNil(parseTyped("25"))
        XCTAssertEqual(parseTyped("830", ampm: "PM"), "20:30")
        XCTAssertEqual(parseTyped("12", ampm: "AM"), "00:00")
        XCTAssertEqual(parseTyped("13", ampm: "AM"), "13:00")   // 24h hour wins
    }

    func testParseRateAndFormats() {
        XCTAssertEqual(parseRate("42,5"), 42.5)
        XCTAssertNil(parseRate(" "))
        XCTAssertTrue(parseRate("abc")!.isNaN)
        XCTAssertEqual(fmtHM(510), "8:30")
        XCTAssertEqual(fmtTime("14:30", twelve: true), "2:30 PM")
        XCTAssertEqual(fmtTime("00:05", twelve: true), "12:05 AM")
    }
}
