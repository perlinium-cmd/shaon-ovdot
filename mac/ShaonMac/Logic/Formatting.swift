import SwiftUI

let gregorian = Calendar(identifier: .gregorian)
private let he = Locale(identifier: "he_IL")

func parseDate(_ s: String) -> Date {
    let p = s.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return .now }
    return gregorian.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? .now
}
func dateStr(_ d: Date) -> String {
    let c = gregorian.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}
func todayStr() -> String { dateStr(.now) }
func yesterdayStr() -> String { dateStr(gregorian.date(byAdding: .day, value: -1, to: .now)!) }
func currentMonth() -> String { String(todayStr().prefix(7)) }
func shiftMonthBy(_ month: String, _ delta: Int) -> String {
    String(dateStr(gregorian.date(byAdding: .month, value: delta, to: parseDate(month + "-01"))!).prefix(7))
}
private func fmt(_ pattern: String, _ d: Date) -> String {
    let f = DateFormatter(); f.locale = he; f.calendar = gregorian; f.setLocalizedDateFormatFromTemplate(pattern); return f.string(from: d)
}
func fmtMonth(_ m: String) -> String { fmt("LLLL yyyy", parseDate(m + "-01")) }
func fmtMonthName(_ m: String) -> String { fmt("LLLL", parseDate(m + "-01")) }
func fmtWeekday(_ d: String) -> String { fmt("EEE", parseDate(d)) }
func fmtDayMonth(_ d: String) -> String { let c = gregorian.dateComponents([.day, .month], from: parseDate(d)); return "\(c.day!)/\(c.month!)" }
/// A rate as it is typed: 45, 45.5, 45.25 (never "45.0"). Rates are whole agorot, so two decimals are exact.
func fmtNum(_ n: Double) -> String {
    var s = String(format: "%.2f", n)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}
func nShifts(_ n: Int) -> String { n == 1 ? "משמרת אחת" : "\(n) משמרות" }

/// hsl → SwiftUI colour (HSL and HSB differ, so convert).
private func hsl(_ hue: Int, _ s: Double, _ l: Double) -> Color {
    let b = l + s * min(l, 1 - l)
    return Color(hue: Double(hue) / 360, saturation: b == 0 ? 0 : 2 * (1 - l / b), brightness: b)
}
/// Same hash and hue table as avatarStyle() on the website, so a name looks identical on both.
func avatarHue(_ name: String) -> Int {
    var h = 0
    for u in name.utf16 { h = (h * 31 + Int(u)) % 360 }
    return [168, 200, 262, 330, 24, 45, 140, 290][h % 8]
}
func avatarColor(_ name: String) -> Color { hsl(avatarHue(name), 0.60, 0.38) }

struct Avatar: View {
    let name: String
    var size: CGFloat = 30
    var body: some View {
        let hue = avatarHue(name)
        Text(String((name.trimmingCharacters(in: .whitespaces).first).map(String.init) ?? "?"))
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(hsl(hue, 0.60, 0.38).mix(with: .primary, by: 0.15))
            .frame(width: size, height: size)
            .background(hsl(hue, 0.65, 0.50).opacity(0.18), in: Circle())
            .accessibilityHidden(true)
    }
}
