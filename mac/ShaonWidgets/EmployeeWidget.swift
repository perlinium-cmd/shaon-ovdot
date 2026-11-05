import SwiftUI
import WidgetKit
import AppIntents
import Charts

// MARK: configuration — pick which employee to show

struct EmployeeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "עובדת"
    static let defaultQuery = EmployeeQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct EmployeeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [EmployeeEntity] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [EmployeeEntity] { all() }
    private func all() -> [EmployeeEntity] { (WidgetStore.load()?.employees ?? []).map { EmployeeEntity(id: $0.id, name: $0.name) } }
}

struct SelectEmployeeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "בחירת עובדת"
    static let description = IntentDescription("איזו עובדת להציג. בלי בחירה – מוצגת מי שמחכה לסכום הגבוה ביותר.")
    @Parameter(title: "עובדת") var employee: EmployeeEntity?
}

// MARK: timeline

struct EmployeeEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
    let emp: WidgetSnapshot.Emp?
}

struct EmployeeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> EmployeeEntry { entry(.sample, id: nil) }
    func snapshot(for configuration: SelectEmployeeIntent, in context: Context) async -> EmployeeEntry {
        entry(WidgetStore.load() ?? (context.isPreview ? .sample : nil), id: configuration.employee?.id)
    }
    func timeline(for configuration: SelectEmployeeIntent, in context: Context) async -> Timeline<EmployeeEntry> {
        Timeline(entries: [entry(WidgetStore.load(), id: configuration.employee?.id)], policy: .after(nextMidnight()))
    }
    /// The chosen employee, or else whoever is owed the most this month.
    private func entry(_ snap: WidgetSnapshot?, id: String?) -> EmployeeEntry {
        let emp = id.flatMap { snap?.emp($0) }
            ?? snap?.employees.max { ($0.unpaid, $0.minutes) < ($1.unpaid, $1.minutes) }
        return EmployeeEntry(date: .now, snap: snap, emp: emp)
    }
}

struct EmployeeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetStore.employeeKind, intent: SelectEmployeeIntent.self, provider: EmployeeProvider()) { e in
            EmployeeWidgetView(entry: e)
        }
        .configurationDisplayName("כרטיס עובדת")
        .description("שעות, משמרת אחרונה וכמה נותר לשלם לעובדת אחת.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: views

struct EmployeeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EmployeeEntry

    var body: some View {
        if let s = entry.snap, let e = entry.emp {
            WidgetShell(url: employeeURL(e.id)) {
                if family == .systemSmall { card(s, e) }
                else {
                    HStack(spacing: 14) {
                        card(s, e)
                        Divider()
                        week(s, e)
                    }
                }
            }
        } else {
            WidgetShell { EmptyState() }
        }
    }

    private func card(_ s: WidgetSnapshot, _ e: WidgetSnapshot.Emp) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Avatar(name: e.name, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.name).font(.headline).lineLimit(1)
                    Text(fmtMonthName(s.month)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if e.shifts == 0 {
                Text("אין משמרות החודש").font(.callout).foregroundStyle(.secondary)
            } else if e.unpaid <= 0 {
                PaidBadge(text: "שולם")
                Text(fmtMoney(e.pay)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(e.paidPay > 0 ? "נותר לתשלום" : "לתשלום").font(.caption).foregroundStyle(.secondary)
                BigMoney(value: e.unpaid, size: 28)
            }
            Spacer(minLength: 4)
            Label {
                Text("\(fmtHM(e.minutes)) · \(nShifts(e.shifts))").monospacedDigit()
            } icon: { Image(systemName: "clock") }
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// This week's hours for her, plus her last shift.
    private func week(_ s: WidgetSnapshot, _ e: WidgetSnapshot.Emp) -> some View {
        let days = weekDays(), today = todayStr()
        let mins = days.map { s.days[$0]?[e.id] ?? 0 }
        let color = avatarColor(e.name)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("השבוע").font(.caption.weight(.semibold))
                Spacer()
                Text(hoursText(mins.reduce(0, +))).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Chart {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    BarMark(x: .value("יום", hebrewDayLetters[i]), y: .value("שעות", Double(mins[i]) / 60), width: .ratio(0.6))
                        .foregroundStyle(d == today ? color : color.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .chartXScale(domain: hebrewDayLetters)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            if let l = e.last {
                Text("אחרונה: \(fmtWeekday(l.date)) \(fmtDayMonth(l.date)) · \(fmtTime(l.in, twelve: s.twelve))–\(fmtTime(l.out, twelve: s.twelve))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("קטן", as: .systemSmall) { EmployeeWidget() } timeline: {
    EmployeeEntry(date: .now, snap: .sample, emp: WidgetSnapshot.sample.employees[0])
}
#Preview("בינוני", as: .systemMedium) { EmployeeWidget() } timeline: {
    EmployeeEntry(date: .now, snap: .sample, emp: WidgetSnapshot.sample.employees[0])
}
