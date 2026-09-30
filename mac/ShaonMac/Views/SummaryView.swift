import SwiftUI

struct SummaryView: View {
    @Environment(AppModel.self) private var model
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        let agg = model.agg
        let rows = model.visibleEmployees().map { ($0, agg[$0.id] ?? Agg()) }
        let tPay = rows.reduce(0) { $0 + $1.1.pay }, tPaid = rows.reduce(0) { $0 + $1.1.paidPay }
        let tMin = rows.reduce(0) { $0 + $1.1.minutes }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    kpi("נותר לתשלום", fmtMoney(tPay - tPaid))
                    kpi("שולם", fmtMoney(tPaid))
                    kpi("שעות", fmtHM(tMin))
                }
                if rows.isEmpty {
                    ContentUnavailableView("אין עובדות להצגה", systemImage: "person.2")
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.0.id) { e, a in
                            Button { onSelect(e.id) } label: {
                                HStack(spacing: 10) {
                                    Avatar(name: e.name)
                                    VStack(alignment: .leading) {
                                        Text(e.name).fontWeight(.medium)
                                        Text("\(a.shifts.count) משמרות · \(fmtHM(a.minutes)) שעות").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(fmtMoney(a.pay)).fontWeight(.semibold).monospacedDigit()
                                        Text(a.shifts.isEmpty ? "" : a.unpaid <= 0 ? "שולם ✓" : a.paidPay > 0 ? "נותר \(fmtMoney(a.unpaid))" : "לא שולם")
                                            .font(.caption).foregroundStyle(a.unpaid <= 0 && !a.shifts.isEmpty ? .green : .secondary)
                                    }
                                }.padding(.vertical, 8).padding(.horizontal, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                        HStack { Text("סה״כ החודש").fontWeight(.semibold); Spacer(); Text(fmtMoney(tPay)).font(.title3.weight(.bold)).monospacedDigit() }.padding(12)
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(20)
        }
        .navigationTitle("סיכום \(fmtMonth(model.month))")
    }
    private func kpi(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(l).font(.caption).foregroundStyle(.secondary); Text(v).font(.title2.weight(.bold)).monospacedDigit() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
