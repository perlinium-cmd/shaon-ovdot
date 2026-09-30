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
func nShifts(_ n: Int) -> String { n == 1 ? "משמרת אחת" : "\(n) משמרות" }

func avatarColor(_ name: String) -> Color {
    var h = 0
    for u in name.unicodeScalars { h = (h * 31 + Int(u.value)) % 360 }
    let hue = [168, 200, 262, 330, 24, 45, 140, 290][h % 8]
    return Color(hue: Double(hue) / 360, saturation: 0.6, brightness: 0.62)
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 30
    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)))
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(avatarColor(name))
            .frame(width: size, height: size)
            .background(avatarColor(name).opacity(0.18), in: Circle())
    }
}
