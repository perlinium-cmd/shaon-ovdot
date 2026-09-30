import Foundation

// Port of the calculation helpers in public/app.js — must stay identical.

func round2(_ n: Double) -> Double { (n * 100).rounded() / 100 }

func toMin(_ t: String) -> Int {
    let p = t.split(separator: ":").compactMap { Int($0) }
    return p.count == 2 ? p[0] * 60 + p[1] : 0
}

/// Minutes worked. If out is earlier than in, the shift crosses midnight.
func shiftMinutes(_ tin: String, _ tout: String) -> Int {
    if tin.isEmpty || tout.isEmpty { return 0 }
    var diff = toMin(tout) - toMin(tin)
    if diff < 0 { diff += 24 * 60 }
    return diff
}

func isOvernight(_ tin: String, _ tout: String) -> Bool {
    !tin.isEmpty && !tout.isEmpty && toMin(tout) < toMin(tin)
}

func specialMinutes(_ s: Shift) -> Double {
    guard let sp = s.special, sp.rate != nil else { return 0 }
    let min = Double(shiftMinutes(s.in, s.out))
    guard let h = sp.hours else { return min }
    return Swift.min(min, h * 60)
}

func effRate(_ emp: Employee?, defaultRate: Double?) -> Double { emp?.rate ?? defaultRate ?? 0 }
func shiftRate(_ s: Shift, _ emp: Employee?, defaultRate: Double?) -> Double { s.rate ?? effRate(emp, defaultRate: defaultRate) }

func shiftPay(_ s: Shift, _ emp: Employee?, defaultRate: Double?) -> Double {
    let min = Double(shiftMinutes(s.in, s.out))
    let sp = specialMinutes(s)
    return ((min - sp) / 60) * shiftRate(s, emp, defaultRate: defaultRate) + (sp / 60) * (s.special?.rate ?? 0)
}

struct Agg {
    var shifts: [Shift] = []
    var minutes = 0
    var pay = 0.0
    var paidPay = 0.0
    var paidCount = 0
    var unpaid: Double { round2(pay - paidPay) }
}

func aggregate(_ shifts: [Shift], employees: [Employee], defaultRate: Double?) -> [String: Agg] {
    var map: [String: Agg] = [:]
    for s in shifts {
        let emp = employees.first { $0.id == s.empId }
        let pay = shiftPay(s, emp, defaultRate: defaultRate)
        var a = map[s.empId] ?? Agg()
        a.shifts.append(s)
        a.minutes += shiftMinutes(s.in, s.out)
        a.pay += pay
        if s.isPaid { a.paidPay += pay; a.paidCount += 1 }
        map[s.empId] = a
    }
    return map
}

func fmtHM(_ min: Int) -> String { "\(min / 60):" + String(format: "%02d", min % 60) }

func fmtMoney(_ n: Double) -> String {
    let v = round2(n)
    let f = NumberFormatter()
    f.locale = Locale(identifier: "he_IL")
    f.numberStyle = .decimal
    f.minimumFractionDigits = v == v.rounded() ? 0 : 2
    f.maximumFractionDigits = 2
    return "\(f.string(from: NSNumber(value: v)) ?? "\(v)") ₪"
}
