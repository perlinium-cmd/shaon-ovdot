import XCTest
@testable import ShaonMac

/// Runs shared/pay-cases.json — the same cases the web app and the Android app are tested with.
final class SharedPayCasesTests: XCTestCase {
    struct File: Decodable { let cases: [Case] }
    struct Case: Decodable {
        struct S: Decodable { let `in`: String; let out: String; let rate: Double?; let special: Special? }
        struct E: Decodable { let rate: Double? }
        let name: String
        let shift: S
        let emp: E?
        let defaultRate: Double?
        let minutes: Int
        let pay: Double
        let overnight: Bool?
    }

    func testSharedCases() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/pay-cases.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        XCTAssertFalse(file.cases.isEmpty)
        for c in file.cases {
            let s = Shift(empId: "e", date: "2026-01-01", month: "2026-01", in: c.shift.in, out: c.shift.out,
                          rate: c.shift.rate, special: c.shift.special)
            let emp = c.emp.map { Employee(id: "e", name: "x", rate: $0.rate) }
            XCTAssertEqual(shiftMinutes(s.in, s.out), c.minutes, c.name)
            XCTAssertEqual(shiftPay(s, emp, defaultRate: c.defaultRate), c.pay, accuracy: 0.001, c.name)
            XCTAssertEqual(isOvernight(s.in, s.out), c.overnight == true, c.name)
        }
    }
}
