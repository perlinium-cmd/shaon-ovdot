import XCTest
@testable import ShaonMac

final class PayTests: XCTestCase {
    func shift(_ i: String, _ o: String, rate: Double? = 40, special: Special? = nil) -> Shift {
        Shift(empId: "e", date: "2026-09-01", month: "2026-09", in: i, out: o, rate: rate, special: special)
    }

    func testMinutes() {
        XCTAssertEqual(shiftMinutes("08:00", "16:30"), 510)
        XCTAssertEqual(shiftMinutes("22:00", "06:00"), 480)   // overnight
        XCTAssertTrue(isOvernight("22:00", "06:00"))
        XCTAssertEqual(shiftMinutes("", "06:00"), 0)
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
