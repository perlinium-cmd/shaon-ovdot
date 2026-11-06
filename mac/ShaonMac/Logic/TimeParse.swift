import Foundation

// Same as parseTyped / parseAmount in public/pay.js (checked against shared/money-cases.json).

private func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

/// Parse typed digits ("8", "830", "0830", "8:30") → "HH:MM"; "" if empty, nil if invalid.
/// In AM/PM mode hours 1–12 use the given ampm; 0 or 13–23 are read as 24h.
/// Only the digits 0–9 count (other numerals, like "½" or "٨", are ignored, never a crash).
func parseTyped(_ text: String, ampm: String? = nil) -> String? {
    let d = String(text.filter(isDigit).prefix(4))
    if d.isEmpty { return "" }
    var h: Int, m: Int
    switch d.count {
    case 1, 2: h = Int(d) ?? 99; m = 0
    case 3: h = Int(d.prefix(1)) ?? 99; m = Int(d.suffix(2)) ?? 99
    default: h = Int(d.prefix(2)) ?? 99; m = Int(d.suffix(2)) ?? 99
    }
    if h > 23 || m > 59 { return nil }
    if let ampm, (1...12).contains(h) { h = (h % 12) + (ampm == "PM" ? 12 : 0) }
    return String(format: "%02d:%02d", h, m)
}

/// A typed amount ("40", "42.5", "42,50") → a number with at most 2 decimals (rounded half up, worked out on the
/// digits, never through a float). nil = empty; .nan = invalid: not a plain non-negative number, or above `max`.
func parseRate(_ v: String, max: Double = 100_000) -> Double? {
    let s = v.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    if s.isEmpty { return nil }
    let parts = s.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2 else { return .nan }
    let ip = String(parts[0]), fp = parts.count == 2 ? String(parts[1]) : ""
    guard ip.allSatisfy(isDigit), fp.allSatisfy(isDigit), !(ip.isEmpty && fp.isEmpty), ip.count <= 12 else { return .nan }
    let frac = Array(fp.padding(toLength: Swift.max(3, fp.count), withPad: "0", startingAt: 0))
    let whole = Int(ip.isEmpty ? "0" : ip) ?? Int.max / 1000
    let a = whole * 100 + Int(String(frac[0...1]))! + (Int(String(frac[2]))! >= 5 ? 1 : 0)
    return Double(a) <= max * 100 ? Double(a) / 100 : .nan
}

/// "HH:MM" (stored, 24h) → text in the chosen format.
func fmtTime(_ t: String, twelve: Bool) -> String {
    if t.isEmpty || !twelve { return t }
    guard let m = parseHM(t) else { return t }
    let h = m / 60
    return "\(h % 12 == 0 ? 12 : h % 12):" + String(format: "%02d", m % 60) + (h < 12 ? " AM" : " PM")
}
