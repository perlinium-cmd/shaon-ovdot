import SwiftUI
import WidgetKit
import Charts

/// "השבוע": hours per day this week (Sunday–Saturday), stacked by employee.
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.weekKind, provider: SnapProvider()) { e in
            WeekWidgetView(snap: e.snap)
        }
        .configurationDisplayName("השבוע")
        .description("שעות העבודה בכל יום השבוע, לפי עובדת, בהשוואה לשבוע שעבר.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct WeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snap: WidgetSnapshot?

    private struct Bar: Identifiable {
        let day: Int, empId: String, name: String, minutes: Int
        var id: String { "\(day)-\(empId)" }
    }

    var body: some View {
        WidgetShell {
            if let s = snap { content(s) } else { EmptyState() }
        }
    }

    private func content(_ s: WidgetSnapshot) -> some View {
        let days = weekDays(), last = weekDays(offset: -1), today = todayStr()
        let names = Dictionary(uniqueKeysWithValues: s.employees.map { ($0.id, $0.name) })
        let bars = days.enumerated().flatMap { i, d in
            (s.days[d] ?? [:]).filter { $0.value > 0 }.map { Bar(day: i, empId: $0.key, name: names[$0.key] ?? "—", minutes: $0.value) }
        }
        let total = bars.reduce(0) { $0 + $1.minutes }
        // Compare with last week up to the same weekday, so mid-week isn't "behind" a full week.
        let todayIdx = days.firstIndex(of: today) ?? 6
        let lastSoFar = last.prefix(todayIdx + 1).reduce(0) { $0 + (s.days[$1]?.values.reduce(0, +) ?? 0) }
        let people = Array(Set(bars.map(\.name))).sorted { $0.localizedCompare($1) == .orderedAscending }
        let colors = seriesColors(people)

        return VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "השבוע", icon: "chart.bar.fill", trailing: "\(fmtDayMonth(days[0]))–\(fmtDayMonth(days[6]))")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fmtHM(total)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                Text("שעות").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                trend(total - lastSoFar)
            }
            if bars.isEmpty {
                Text("אין עדיין משמרות השבוע").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(bars) { b in
                    BarMark(x: .value("יום", hebrewDayLetters[b.day]), y: .value("שעות", Double(b.minutes) / 60), width: .ratio(0.62))
                        .foregroundStyle(by: .value("עובדת", b.name))
                }
                .chartXScale(domain: hebrewDayLetters)
                .chartForegroundStyleScale(domain: people, range: people.map { colors[$0]! })
                .chartLegend(family == .systemLarge ? .hidden : .automatic)
                .chartLegend(position: .bottom, spacing: 4)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        AxisValueLabel().font(.system(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            let label = v.as(String.self) ?? ""
                            Text(label).font(.system(size: 10, weight: label == hebrewDayLetters[todayIdx] ? .bold : .regular))
                                .foregroundStyle(label == hebrewDayLetters[todayIdx] ? brand : .secondary)
                        }
                    }
                }
                if family == .systemLarge { legend(s, days: days, colors: colors) }
            }
        }
    }

    @ViewBuilder
    private func trend(_ delta: Int) -> some View {
        if delta != 0 {
            Label("\(fmtHM(abs(delta))) \(delta > 0 ? "יותר" : "פחות") משבוע שעבר", systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    /// Large size: per-employee hours for the week.
    private func legend(_ s: WidgetSnapshot, days: [String], colors: [String: Color]) -> some View {
        let rows = s.employees
            .map { e in (e, days.reduce(0) { $0 + (s.days[$1]?[e.id] ?? 0) }) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let top = rows.first?.1 ?? 1
        return VStack(spacing: 7) {
            ForEach(rows.prefix(4), id: \.0.id) { e, min in
                Link(destination: employeeURL(e.id)) {
                    HStack(spacing: 8) {
                        Avatar(name: e.name, size: 22)
                        Text(e.name).font(.caption.weight(.medium)).frame(width: 64, alignment: .leading).lineLimit(1)
                        PaidBar(fraction: Double(min) / Double(top), color: colors[e.name] ?? avatarColor(e.name), height: 6)
                        Text(fmtHM(min)).font(.caption).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }
}

#Preview("בינוני", as: .systemMedium) { WeekWidget() } timeline: { SnapEntry(date: .now, snap: .sample) }
#Preview("גדול", as: .systemLarge) { WeekWidget() } timeline: { SnapEntry(date: .now, snap: .sample) }
