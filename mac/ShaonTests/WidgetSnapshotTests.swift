import XCTest
@testable import ShaonMac

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotTotalsAndDays() {
        let emps = [Employee(id: "a", name: "דנה", rate: nil), Employee(id: "b", name: "מיכל", rate: 50, active: false),
                    Employee(id: "c", name: "נועה", rate: nil, active: false)]
        let cur = [
            Shift(id: "1", empId: "a", date: "2026-10-01", month: "2026-10", in: "08:00", out: "16:00", paid: true),
            Shift(id: "2", empId: "a", date: "2026-10-02", month: "2026-10", in: "22:00", out: "02:00"),
            Shift(id: "3", empId: "b", date: "2026-10-02", month: "2026-10", in: "10:00", out: "12:00"),
        ]
        let prev = [Shift(id: "4", empId: "a", date: "2026-09-30", month: "2026-09", in: "09:00", out: "10:00")]
        let s = makeWidgetSnapshot(month: "2026-10", settings: AppSettings(defaultRate: 40), employees: emps, current: cur, previous: prev)

        // Archived without shifts this month is dropped; archived with shifts stays.
        XCTAssertEqual(s.employees.map(\.id).sorted(), ["a", "b"])
        let a = s.emp("a")!
        XCTAssertEqual(a.minutes, 12 * 60)
        XCTAssertEqual(a.pay, 480)
        XCTAssertEqual(a.unpaid, 160)
        XCTAssertEqual(a.last, .init(date: "2026-10-02", in: "22:00", out: "02:00"))
        XCTAssertEqual(s.emp("b")!.pay, 100)
        XCTAssertEqual(s.remaining, 260)
        XCTAssertEqual(s.paidFraction, 320.0 / 580, accuracy: 0.0001)
        XCTAssertEqual(s.days["2026-09-30"]?["a"], 60)   // previous month feeds the weekly chart
        XCTAssertEqual(s.days["2026-10-02"], ["a": 240, "b": 120])
    }
}
