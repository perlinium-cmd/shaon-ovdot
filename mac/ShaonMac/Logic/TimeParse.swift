import Foundation

/// Parse typed digits ("8", "830", "0830", "8:30") → "HH:MM"; "" if empty, nil if invalid.
/// In AM/PM mode hours 1–12 use the given ampm; 0 or 13–23 are read as 24h.
func parseTyped(_ text: String, ampm: String? = nil) -> String? {
    let d = String(text.filter(\.isNumber).prefix(4))
    if d.isEmpty { return "" }
    var h: Int, m: Int
    switch d.count {
    case 1, 2: h = Int(d)!; m = 0
    case 3: h = Int(d.prefix(1))!; m = Int(d.suffix(2))!
    default: h = Int(d.prefix(2))!; m = Int(d.suffix(2))!
    }
    if h > 23 || m > 59 { return nil }
    if let ampm, (1...12).contains(h) { h = (h % 12) + (ampm == "PM" ? 12 : 0) }
    return String(format: "%02d:%02d", h, m)
}

/// nil = empty, .nan = invalid, otherwise the rate (accepts comma or dot).
func parseRate(_ v: String) -> Double? {
    let s = v.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    if s.isEmpty { return nil }
    guard let n = Double(s), n.isFinite, n >= 0 else { return .nan }
    return round2(n)
}

/// "HH:MM" (stored, 24h) → text in the chosen format.
func fmtTime(_ t: String, twelve: Bool) -> String {
    if t.isEmpty || !twelve { return t }
    let p = t.split(separator: ":").compactMap { Int($0) }
    guard p.count == 2 else { return t }
    return "\(p[0] % 12 == 0 ? 12 : p[0] % 12):" + String(format: "%02d", p[1]) + (p[0] < 12 ? " AM" : " PM")
}
