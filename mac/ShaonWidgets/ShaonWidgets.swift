import SwiftUI
import WidgetKit

@main
struct ShaonWidgets: WidgetBundle {
    var body: some Widget {
        QuickWidget()
        MonthWidget()
        EmployeeWidget()
        WeekWidget()
    }
}

let brand = Color(red: 0.06, green: 0.46, blue: 0.43)

// MARK: timeline

struct SnapEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

/// The app pushes reloads whenever data changes; the midnight refresh only moves "today" forward.
func nextMidnight() -> Date { gregorian.startOfDay(for: gregorian.date(byAdding: .day, value: 1, to: .now)!) }

struct SnapProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapEntry { SnapEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SnapEntry) -> Void) {
        completion(SnapEntry(date: .now, snap: WidgetStore.load() ?? (context.isPreview ? .sample : nil)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapEntry>) -> Void) {
        completion(Timeline(entries: [SnapEntry(date: .now, snap: WidgetStore.load())], policy: .after(nextMidnight())))
    }
}

// MARK: deep links (handled in ShaonApp.onOpenURL)

let summaryURL = URL(string: "shaon://summary")!
func employeeURL(_ id: String) -> URL { URL(string: "shaon://employee/\(id)")! }

// MARK: shared pieces

/// Common frame: RTL like the app, tinted background, tap opens the app.
struct WidgetShell<Content: View>: View {
    var url: URL = summaryURL
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.layoutDirection, .rightToLeft)
            .widgetURL(url)
            .containerBackground(for: .widget) {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    LinearGradient(colors: [brand.opacity(0.16), brand.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
    }
}

struct WidgetHeader: View {
    let title: String
    var icon = "clock.badge.checkmark"
    var trailing: String?
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(brand).widgetAccentable()
            Text(title).fontWeight(.semibold)
            Spacer(minLength: 4)
            if let trailing { Text(trailing).foregroundStyle(.secondary).monospacedDigit() }
        }
        .font(.caption)
        .lineLimit(1)
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.badge.checkmark").font(.title).foregroundStyle(brand).widgetAccentable()
            Text("שעון עובדות").font(.headline)
            Text("פתחו את האפליקציה והתחברו כדי לראות כאן נתונים").font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Paid share of the month as a ring.
struct PaidRing<Center: View>: View {
    let fraction: Double
    var lineWidth: CGFloat = 9
    @ViewBuilder var center: Center
    var body: some View {
        ZStack {
            Circle().stroke(brand.opacity(0.15), lineWidth: lineWidth)
            Circle().trim(from: 0, to: fraction)
                .stroke(brand.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            center
        }
    }
}

/// Paid share as a thin capsule. Fills from the leading (right, in RTL) edge.
struct PaidBar: View {
    let fraction: Double
    var color: Color = brand
    var height: CGFloat = 6
    var body: some View {
        Capsule().fill(color.opacity(0.15))
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(color).frame(width: max(fraction > 0 ? height : 0, g.size.width * fraction)).widgetAccentable()
                }
            }
            .frame(height: height)
            .clipShape(Capsule())
    }
}

/// Big rounded money figure that shrinks rather than truncates.
struct BigMoney: View {
    let value: Double
    var size: CGFloat = 28
    var body: some View {
        Text(fmtMoney(value))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            .contentTransition(.numericText(value: value))
    }
}

struct PaidBadge: View {
    var text = "הכול שולם"
    var body: some View {
        Label(text, systemImage: "checkmark.seal.fill")
            .font(.callout.weight(.semibold)).foregroundStyle(.green)
    }
}

let hebrewDayLetters = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]

/// Sunday…Saturday of the week containing `date` (Israeli week), as YYYY-MM-DD.
func weekDays(of date: Date = .now, offset: Int = 0) -> [String] {
    var cal = gregorian; cal.firstWeekday = 1
    let start = cal.dateInterval(of: .weekOfYear, for: date)!.start
    return (0..<7).map { dateStr(cal.date(byAdding: .day, value: $0 + offset * 7, to: start)!) }
}

/// Chart colors: each name keeps its avatar color unless an earlier name already took that hue.
func seriesColors(_ names: [String]) -> [String: Color] {
    let palette = [168, 200, 262, 330, 24, 45, 140, 290].map { Color(hue: Double($0) / 360, saturation: 0.6, brightness: 0.62) }
    var used = Set<Int>(), out: [String: Color] = [:]
    for n in names {
        let own = palette.firstIndex(of: avatarColor(n)) ?? 0
        let i = used.contains(own) ? (0..<palette.count).first { !used.contains($0) } ?? own : own
        used.insert(i); out[n] = palette[i]
    }
    return out
}

func hoursText(_ min: Int) -> String { "\(fmtHM(min)) שעות" }

// MARK: sample data for the widget gallery

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let m = currentMonth()
        var days: [String: [String: Int]] = [:]
        for (i, d) in weekDays().enumerated() where d <= todayStr() {
            days[d] = ["a": [480, 510, 0, 450, 480, 300, 0][i], "b": [0, 420, 480, 390, 0, 240, 0][i], "c": [300, 0, 360, 0, 420, 0, 0][i]]
        }
        return WidgetSnapshot(month: m, twelve: false, employees: [
            .init(id: "a", name: "דנה", minutes: 4860, pay: 3240, paidPay: 2160, shifts: 10, paidShifts: 7, last: .init(date: todayStr(), in: "08:00", out: "16:00")),
            .init(id: "b", name: "מיכל", minutes: 3720, pay: 2790, paidPay: 2790, shifts: 8, paidShifts: 8, last: .init(date: yesterdayStr(), in: "09:00", out: "16:30")),
            .init(id: "c", name: "נועה", minutes: 2280, pay: 1520, paidPay: 0, shifts: 6, paidShifts: 0, last: .init(date: yesterdayStr(), in: "12:00", out: "19:00")),
        ], days: days, updatedAt: .now)
    }
}
