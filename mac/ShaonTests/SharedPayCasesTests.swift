import XCTest
@testable import ShaonMac

/// Runs shared/pay-cases.json and shared/money-cases.json — the same cases the web app and the Android app are tested with.
final class SharedPayCasesTests: XCTestCase {
    struct File: Decodable { let cases: [Case] }
    struct Case: Decodable {
        struct S: Decodable { let `in`: String; let out: String; let rate: Double?; let special: Special? }
        struct E: Decodable { let rate: Double? }
        let name: String
        let date: String?
        let shift: S
        let emp: E?
        let defaultRate: Double?
        let minutes: Int
        let payAgorot: Int
        let overnight: Bool?
    }

    /// shared/*.json, copied into the test bundle (see project.yml).
    private func shared(_ name: String) throws -> Data {
        let parts = name.split(separator: ".")
        let url = try XCTUnwrap(Bundle(for: SharedPayCasesTests.self).url(forResource: String(parts[0]), withExtension: String(parts[1])),
                                "\(name) is missing from the test bundle")
        return try Data(contentsOf: url)
    }

    func testSharedCases() throws {
        let file = try JSONDecoder().decode(File.self, from: shared("pay-cases.json"))
        XCTAssertGreaterThan(file.cases.count, 30)
        for c in file.cases {
            let date = c.date ?? "2026-01-01"
            let s = Shift(empId: "e", date: date, month: String(date.prefix(7)), in: c.shift.in, out: c.shift.out,
                          rate: c.shift.rate, special: c.shift.special)
            let emp = c.emp.map { Employee(id: "e", name: "x", rate: $0.rate) }
            XCTAssertEqual(shiftMinutes(s.date, s.in, s.out), c.minutes, c.name)
            XCTAssertEqual(shiftPayAgorot(s, emp, defaultRate: c.defaultRate), c.payAgorot, c.name)
            XCTAssertEqual(shiftPay(s, emp, defaultRate: c.defaultRate), Double(c.payAgorot) / 100, c.name)
            XCTAssertEqual(isOvernight(s.in, s.out), c.overnight == true, c.name)
        }
    }

    func testMoneyCases() throws {
        let json = try JSONSerialization.jsonObject(with: shared("money-cases.json")) as! [String: Any]
        for pair in json["toAgorot"] as! [[Any]] {
            let x = (pair[0] as! NSNumber).doubleValue, want = (pair[1] as! NSNumber).intValue
            XCTAssertEqual(toAgorot(x), want, "toAgorot(\(x))")
            XCTAssertEqual(round2(x), Double(want) / 100, "round2(\(x))")
        }
        XCTAssertNil(toAgorot(.nan)); XCTAssertNil(toAgorot(.infinity))
        for pair in json["parseAmount"] as! [[Any]] {
            let text = pair[0] as! String
            let got = parseRate(text)
            switch pair[1] {
            case is NSNull: XCTAssertNil(got, "\"\(text)\"")
            case let s as String where s == "invalid": XCTAssertTrue(got?.isNaN == true, "\"\(text)\" should be invalid, got \(String(describing: got))")
            case let n as NSNumber: XCTAssertEqual(got, n.doubleValue, "\"\(text)\"")
            default: XCTFail("bad case \(pair)")
            }
        }
        for pair in json["parseHM"] as! [[Any]] {
            let text = pair[0] as! String
            XCTAssertEqual(parseHM(text), (pair[1] as? NSNumber)?.intValue, "\"\(text)\"")
        }
        for c in json["parseTyped"] as! [[Any]] {
            let text = c[0] as! String, ampm = c[1] as? String
            XCTAssertEqual(parseTyped(text, ampm: ampm), c[2] as? String, "\"\(text)\" \(ampm ?? "")")
        }
        // Other numerals are ignored, never a crash.
        XCTAssertEqual(parseTyped("½"), "")
        XCTAssertEqual(parseTyped("٨٣٠"), "")
    }
}
