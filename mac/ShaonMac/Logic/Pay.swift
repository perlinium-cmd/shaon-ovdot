import Foundation

// Port of public/pay.js — must stay identical. All three apps are tested against shared/pay-cases.json
// and shared/money-cases.json.
//
// Money is exact: every amount is a whole number of agorot. A shift's pay is worked out exactly and rounded
// once, to the nearest agora (half up); totals add up those whole agorot, so rows always sum to their total.
// Hours are real time in Israel: on the nights the clock moves, 22:00–06:00 is 7 or 9 hours, not 8.

let shiftZone = TimeZone(identifier: "Asia/Jerusalem")!
private let dayMin = 24 * 60
private let h12 = 12.0 * 3600 * 1000

// MARK: times and dates

private func asciiDigits<S: StringProtocol>(_ s: S) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber } }

/// "HH:MM" (or "H:MM") → minutes since midnight; nil if empty or not a valid time.
func parseHM(_ t: String) -> Int? {
    let p = t.split(separator: ":", omittingEmptySubsequences: false)
    guard p.count == 2, (1...2).contains(p[0].count), p[1].count == 2, asciiDigits(p[0]), asciiDigits(p[1]),
          let h = Int(p[0]), let m = Int(p[1]), h <= 23, m <= 59 else { return nil }
    return h * 60 + m
}
/// Minutes since midnight, 0 when not a valid time.
func toMin(_ t: String) -> Int { parseHM(t) ?? 0 }

struct YMD: Equatable { let y: Int, m: Int, d: Int }
private func isLeap(_ y: Int) -> Bool { y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) }
private func daysIn(_ y: Int, _ m: Int) -> Int { [31, isLeap(y) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1] }

/// "YYYY-MM-DD" → a real calendar date, else nil.
func parseYMD(_ s: String) -> YMD? {
    let p = s.split(separator: "-", omittingEmptySubsequences: false)
    guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2, p.allSatisfy({ asciiDigits($0) }),
          let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
          y >= 1900, (1...12).contains(m), d >= 1, d <= daysIn(y, m) else { return nil }
    return YMD(y: y, m: m, d: d)
}
private func nextDay(_ v: YMD) -> YMD {
    v.d < daysIn(v.y, v.m) ? YMD(y: v.y, m: v.m, d: v.d + 1) : v.m < 12 ? YMD(y: v.y, m: v.m + 1, d: 1) : YMD(y: v.y + 1, m: 1, d: 1)
}
/// Days since 1970-01-01 (proleptic Gregorian), so dates need no Calendar.
private func epochDay(_ v: YMD) -> Int {
    let y = v.m <= 2 ? v.y - 1 : v.y
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let doy = (153 * ((v.m + 9) % 12) + 2) / 5 + v.d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
}
private func utcMidnight(_ v: YMD) -> Double { Double(epochDay(v)) * 86_400_000 }

/// Israel's offset from UTC, in ms, at a moment (+2h in winter, +3h in summer).
func zoneOffsetMs(_ utcMs: Double) -> Double {
    Double(shiftZone.secondsFromGMT(for: Date(timeIntervalSince1970: utcMs / 1000))) * 1000
}

/// The moment (ms since 1970) of a wall-clock time in Israel. Like java.time: in the hour that repeats in
/// autumn, the earlier (summer) moment; a time skipped in spring is moved forward by the gap (02:30 → 03:30).
func zonedMs(_ day: YMD, _ minOfDay: Int) -> Double {
    let naive = utcMidnight(day) + Double(minOfDay) * 60000
    let before = zoneOffsetMs(naive - h12), after = zoneOffsetMs(naive + h12)
    let c1 = naive - before, c2 = naive - after
    let ok1 = zoneOffsetMs(c1) == before, ok2 = zoneOffsetMs(c2) == after
    if ok1 && ok2 { return min(c1, c2) }
    if ok2 { return c2 }
    return c1
}

/// True when the clock does not move from the start of `day` until 2 days later (all days but 2 a year).
private func steadyFrom(_ day: YMD) -> Bool {
    let t = utcMidnight(day)
    return zoneOffsetMs(t - 6 * 3_600_000) == zoneOffsetMs(t + 54 * 3_600_000)
}

/// Minutes worked on `date` (the day of the clock-in). If out is earlier than in, the shift ends the next day.
/// Real time: counts the hour the clock moves. 0 when a time is missing or invalid, or in equals out.
func shiftMinutes(_ date: String, _ tin: String, _ tout: String) -> Int {
    guard let a = parseHM(tin), let b = parseHM(tout), a != b else { return 0 }
    let wall = b > a ? b - a : b - a + dayMin
    guard let d = parseYMD(date), !steadyFrom(d) else { return wall }
    let start = zonedMs(d, a)
    let end = zonedMs(b > a ? d : nextDay(d), b)
    let real = Int(((end - start) / 60000).rounded())
    return real > 0 ? real : wall
}

/// The same shift by the clock on the wall (ignores the clock moving), for showing the difference.
func wallMinutes(_ tin: String, _ tout: String) -> Int {
    guard let a = parseHM(tin), let b = parseHM(tout), a != b else { return 0 }
    return b > a ? b - a : b - a + dayMin
}

func isOvernight(_ tin: String, _ tout: String) -> Bool {
    guard let a = parseHM(tin), let b = parseHM(tout) else { return false }
    return b < a
}

// MARK: money

/// Exact whole agorot of an amount in shekels, rounded half up (half away from zero below 0); nil if not finite.
/// Reads the number's shortest decimal form, so 1.005 → 101 (not 100).
func toAgorot(_ x: Double) -> Int? {
    guard x.isFinite else { return nil }
    let s = "\(abs(x))"
    var mant = Substring(s), exp = 0
    if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
        mant = s[..<e]
        guard let ev = Int(s[s.index(after: e)...]) else { return nil }
        exp = ev
    }
    let parts = mant.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count), asciiDigits(parts[0]) else { return nil }
    let frac = parts.count == 2 ? String(parts[1]) : ""
    guard frac.isEmpty || asciiDigits(frac) else { return nil }
    let digits = Array(String(parts[0]) + frac)
    let point = parts[0].count + exp + 2   // where the decimal point falls after ×100
    var whole = 0, next = 0
    if point <= 0 {
        next = point == 0 ? Int(String(digits[0]))! : 0
    } else if point >= digits.count {
        guard let w = Int(String(digits) + String(repeating: "0", count: point - digits.count)) else { return nil }
        whole = w
    } else {
        guard let w = Int(String(digits[..<point])) else { return nil }
        whole = w; next = Int(String(digits[point]))!
    }
    let a = whole + (next >= 5 ? 1 : 0)
    return x < 0 && a != 0 ? -a : a
}

/// Rounded to the agora, as a number (2 decimals at most).
func round2(_ n: Double) -> Double { Double(toAgorot(n) ?? 0) / 100 }

/// num / den rounded to the nearest whole number, half away from zero (den > 0).
private func divRound(_ num: Int, _ den: Int) -> Int {
    let q = (2 * abs(num) + den) / (2 * den)
    return num < 0 ? -q : q
}

private func finite(_ x: Double?) -> Double? { x.flatMap { $0.isFinite ? $0 : nil } }

/// Hourly rate for an employee: their own rate, else the default rate, else 0.
func effRate(_ emp: Employee?, defaultRate: Double?) -> Double { finite(emp?.rate) ?? finite(defaultRate) ?? 0 }
/// Hourly rate for a shift: a rate set on the shift wins over the employee's rate.
func shiftRate(_ s: Shift, _ emp: Employee?, defaultRate: Double?) -> Double { finite(s.rate) ?? effRate(emp, defaultRate: defaultRate) }

private func specialOf(_ s: Shift) -> (rate: Double, hours: Double?)? {
    guard let r = finite(s.special?.rate) else { return nil }
    return (r, finite(s.special?.hours))
}

/// Minutes of a shift paid at its special rate (all of it, or only `special.hours`). Can have a fraction.
func specialMinutes(_ s: Shift) -> Double {
    guard let sp = specialOf(s) else { return 0 }
    let min = Double(shiftMinutes(s.date, s.in, s.out))
    guard let h = sp.hours else { return min }
    return Swift.min(min, Swift.max(0, h * 60))
}

/// Pay for one shift in whole agorot. Worked out exactly in fifths of a minute (0.01 hour = 0.6 minute), rounded once.
func shiftPayAgorot(_ s: Shift, _ emp: Employee?, defaultRate: Double?) -> Int {
    let total = shiftMinutes(s.date, s.in, s.out)
    guard total > 0 else { return 0 }
    let units = total * 5
    let sp = specialOf(s)
    var spUnits = 0
    if let sp { spUnits = sp.hours == nil ? units : Swift.min(units, Swift.max(0, (toAgorot(sp.hours!) ?? 0) * 3)) }
    let amount = (units - spUnits) * (toAgorot(shiftRate(s, emp, defaultRate: defaultRate)) ?? 0)
        + spUnits * (sp.flatMap { toAgorot($0.rate) } ?? 0)
    return divRound(amount, 300)
}

/// Pay for one shift in shekels (always a whole number of agorot).
func shiftPay(_ s: Shift, _ emp: Employee?, defaultRate: Double?) -> Double {
    Double(shiftPayAgorot(s, emp, defaultRate: defaultRate)) / 100
}

struct Agg {
    var shifts: [Shift] = []
    var minutes = 0
    var payAgorot = 0
    var paidAgorot = 0
    var paidCount = 0
    var pay: Double { Double(payAgorot) / 100 }
    var paidPay: Double { Double(paidAgorot) / 100 }
    var unpaid: Double { Double(payAgorot - paidAgorot) / 100 }
    /// Finished shifts that are not marked paid (a running shift has no pay yet).
    var unpaidShifts: [Shift] { shifts.filter { !$0.isPaid && !$0.isOpen } }
    /// Every finished shift is marked paid (and there is at least one).
    var allPaid: Bool { shifts.contains { !$0.isOpen } && unpaidShifts.isEmpty }
}

func aggregate(_ shifts: [Shift], employees: [Employee], defaultRate: Double?) -> [String: Agg] {
    var map: [String: Agg] = [:]
    for s in shifts {
        let emp = employees.first { $0.id == s.empId }
        let p = shiftPayAgorot(s, emp, defaultRate: defaultRate)
        var a = map[s.empId] ?? Agg()
        a.shifts.append(s)
        a.minutes += shiftMinutes(s.date, s.in, s.out)
        a.payAgorot += p
        if s.isPaid { a.paidAgorot += p; a.paidCount += 1 }
        map[s.empId] = a
    }
    return map
}

func fmtHM(_ min: Int) -> String { "\(min / 60):" + String(format: "%02d", min % 60) }

func fmtMoney(_ n: Double) -> String {
    let a = toAgorot(n) ?? 0
    let f = NumberFormatter()
    f.locale = Locale(identifier: "he_IL")
    f.numberStyle = .decimal
    f.minimumFractionDigits = a % 100 == 0 ? 0 : 2
    f.maximumFractionDigits = 2
    return "\(f.string(from: NSDecimalNumber(mantissa: UInt64(abs(a)), exponent: -2, isNegative: a < 0)) ?? "\(Double(a) / 100)") ₪"
}
