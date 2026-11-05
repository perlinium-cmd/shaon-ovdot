import SwiftUI
import WidgetKit

/// "החודש במבט": how much is left to pay this month, how much was paid, and hours worked.
struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.monthKind, provider: SnapProvider()) { e in
            MonthWidgetView(snap: e.snap)
        }
        .configurationDisplayName("החודש במבט")
        .description("כמה נותר לשלם, כמה כבר שולם, ומי עוד מחכה לתשלום.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snap: WidgetSnapshot?

    var body: some View {
        WidgetShell {
            if let s = snap {
                switch family {
                case .systemSmall: small(s)
                case .systemLarge: large(s)
                default: medium(s)
                }
            } else { EmptyState() }
        }
    }

    // MARK: small — the one number that matters

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: fmtMonthName(s.month), icon: "calendar")
            Spacer(minLength: 4)
            remaining(s, size: 30)
            Spacer(minLength: 6)
            PaidBar(fraction: s.paidFraction)
            HStack {
                Text(hoursText(s.totalMinutes))
                Spacer(minLength: 2)
                Text(nShifts(s.totalShifts))
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            .padding(.top, 5)
        }
    }

    @ViewBuilder
    private func remaining(_ s: WidgetSnapshot, size: CGFloat) -> some View {
        if s.totalShifts == 0 {
            Text("אין עדיין משמרות החודש").font(.callout).foregroundStyle(.secondary)
        } else if s.remaining <= 0 {
            PaidBadge()
            Text("סה״כ \(fmtMoney(s.totalPay))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        } else {
            Text("נותר לתשלום").font(.caption).foregroundStyle(.secondary)
            BigMoney(value: s.remaining, size: size)
        }
    }

    // MARK: medium — ring + key figures

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 16) {
            ring(s, size: 104)
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(title: fmtMonth(s.month), icon: "calendar")
                Spacer(minLength: 4)
                remaining(s, size: 30)
                Spacer(minLength: 6)
                HStack(spacing: 0) {
                    stat("שעות", fmtHM(s.totalMinutes))
                    stat("משמרות", "\(s.totalShifts)")
                    stat("שולם", fmtMoney(s.totalPaid))
                }
            }
        }
    }

    private func ring(_ s: WidgetSnapshot, size: CGFloat) -> some View {
        PaidRing(fraction: s.paidFraction, lineWidth: size * 0.1) {
            VStack(spacing: 0) {
                Text("\(Int((s.paidFraction * 100).rounded()))%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded)).monospacedDigit()
                Text("שולם").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: large — who is still waiting to be paid

    private func large(_ s: WidgetSnapshot) -> some View {
        let worked = s.employees.filter { $0.shifts > 0 }
            .sorted { ($0.unpaid, $0.pay) > ($1.unpaid, $1.pay) }
        let shown = Array(worked.prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            medium(s).frame(height: 112)
            Divider()
            Text(s.remaining > 0 ? "מחכות לתשלום" : "עובדות החודש").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if shown.isEmpty {
                Text("אין עדיין משמרות החודש").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(shown) { e in Link(destination: employeeURL(e.id)) { employeeRow(e) } }
                }
                Spacer(minLength: 0)
                if worked.count > shown.count {
                    Text("ועוד \(worked.count - shown.count)…").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func employeeRow(_ e: WidgetSnapshot.Emp) -> some View {
        HStack(spacing: 10) {
            Avatar(name: e.name, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(e.name).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    if e.unpaid > 0 {
                        Text(fmtMoney(e.unpaid)).font(.callout.weight(.semibold)).monospacedDigit()
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                PaidBar(fraction: e.pay > 0 ? e.paidPay / e.pay : 0, color: avatarColor(e.name), height: 4)
            }
        }
    }
}

#Preview("קטן", as: .systemSmall) { MonthWidget() } timeline: { SnapEntry(date: .now, snap: .sample) }
#Preview("בינוני", as: .systemMedium) { MonthWidget() } timeline: { SnapEntry(date: .now, snap: .sample) }
#Preview("גדול", as: .systemLarge) { MonthWidget() } timeline: { SnapEntry(date: .now, snap: .sample) }
