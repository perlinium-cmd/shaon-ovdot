import SwiftUI
import WidgetKit
import AppIntents

/// Widget button: clock an employee in, or out (which queues the shift for the app to save).
struct ToggleClockIntent: AppIntent {
    static let title: LocalizedStringResource = "כניסה / יציאה ממשמרת"
    static let isDiscoverable = false
    @Parameter(title: "עובדת") var empId: String

    init() {}
    init(empId: String) { self.empId = empId }

    func perform() async throws -> some IntentResult {
        if QuickClock.toggle(empId) != nil { QuickClock.postChanged() }
        return .result()
    }
}

struct QuickEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
    let clock: ClockState
}

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: .now, snap: .sample, clock: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
        let snap = WidgetStore.load()
        completion(QuickEntry(date: .now, snap: snap ?? (context.isPreview ? .sample : nil), clock: snap == nil && context.isPreview ? .sample : QuickClock.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        completion(Timeline(entries: [QuickEntry(date: .now, snap: WidgetStore.load(), clock: QuickClock.load())], policy: .after(nextMidnight())))
    }
}

struct QuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.quickKind, provider: QuickProvider()) { e in
            QuickWidgetView(entry: e)
        }
        .configurationDisplayName("רישום מהיר")
        .description("לחיצה אחת בתחילת המשמרת ואחת בסופה – והמשמרת נרשמת. ＋ פותח טופס הוספה ידני.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickEntry

    private var capacity: Int { family == .systemSmall ? 2 : family == .systemMedium ? 4 : 8 }

    /// Clocked-in first, then whoever worked most recently.
    private func people(_ s: WidgetSnapshot) -> [WidgetSnapshot.Emp] {
        let running = entry.clock.running
        return s.employees.filter { $0.active || running[$0.id] != nil }
            .sorted {
                let a = running[$0.id], b = running[$1.id]
                if (a != nil) != (b != nil) { return a != nil }
                return ($0.last?.date ?? "", $1.name) > ($1.last?.date ?? "", $0.name)
            }
            .prefix(capacity).map { $0 }
    }

    var body: some View {
        WidgetShell {
            if let s = entry.snap {
                let list = people(s)
                VStack(alignment: .leading, spacing: 8) {
                    let on = entry.clock.running.count
                    WidgetHeader(title: "רישום מהיר", icon: "stopwatch", trailing: on > 0 ? "\(on) בעבודה" : nil)
                    if list.isEmpty {
                        Text("אין עובדות פעילות").font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if family == .systemSmall {
                        VStack(spacing: 6) { ForEach(list) { tile($0, compact: true) } }
                        Spacer(minLength: 0)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(list) { tile($0, compact: false) }
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else { EmptyState() }
        }
    }

    private func tile(_ e: WidgetSnapshot.Emp, compact: Bool) -> some View {
        let start = entry.clock.running[e.id]
        let color = avatarColor(e.name)
        return HStack(spacing: 8) {
            Button(intent: ToggleClockIntent(empId: e.id)) {
                Image(systemName: start == nil ? "play.fill" : "stop.fill")
                    .font(.system(size: compact ? 11 : 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                    .background(start == nil ? color : .red, in: Circle())
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
            .help(start == nil ? "תחילת משמרת" : "סיום משמרת")

            VStack(alignment: .leading, spacing: 0) {
                Text(e.name).font((compact ? Font.caption : .callout).weight(.semibold)).lineLimit(1)
                if let start {
                    Text(start, style: .timer).font(.caption2.weight(.medium)).foregroundStyle(.red).monospacedDigit()
                } else {
                    Text(lastLine(e)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !compact {
                Link(destination: employeeURL(e.id)) {
                    Image(systemName: "plus").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(.quaternary, in: Circle())
                }
                .help("הוספת משמרת ידנית")
            }
        }
        .padding(compact ? 6 : 8)
        .background(start == nil ? AnyShapeStyle(.background.opacity(0.55)) : AnyShapeStyle(Color.red.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func lastLine(_ e: WidgetSnapshot.Emp) -> String {
        guard let l = e.last else { return "טרם עבדה" }
        if l.date == todayStr() { return "היום עד \(fmtTime(l.out, twelve: entry.snap?.twelve ?? false))" }
        if l.date == yesterdayStr() { return "אתמול" }
        return "\(fmtWeekday(l.date)) \(fmtDayMonth(l.date))"
    }
}

extension ClockState {
    static var sample: ClockState { ClockState(running: ["a": .now.addingTimeInterval(-2.5 * 3600)]) }
}

#Preview("קטן", as: .systemSmall) { QuickWidget() } timeline: { QuickEntry(date: .now, snap: .sample, clock: .sample) }
#Preview("בינוני", as: .systemMedium) { QuickWidget() } timeline: { QuickEntry(date: .now, snap: .sample, clock: .sample) }
#Preview("גדול", as: .systemLarge) { QuickWidget() } timeline: { QuickEntry(date: .now, snap: .sample, clock: .sample) }
