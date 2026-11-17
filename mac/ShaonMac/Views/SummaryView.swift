import SwiftUI

struct SummaryView: View {
    @Environment(AppModel.self) private var model
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        let agg = model.agg
        let rows = model.visibleEmployees().map { ($0, agg[$0.id] ?? Agg()) }
        // Whole agorot: totals are exactly the sum of the rows.
        let tPayA = rows.reduce(0) { $0 + $1.1.payAgorot }, tPaidA = rows.reduce(0) { $0 + $1.1.paidAgorot }
        let tPay = Double(tPayA) / 100, tPaid = Double(tPaidA) / 100
        let tMin = rows.reduce(0) { $0 + $1.1.minutes }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    kpi("נותר לתשלום", fmtMoney(Double(tPayA - tPaidA) / 100))
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
                                        let rates = Set(a.shifts.map { shiftRate($0, e, defaultRate: model.defaultRate) })
                                        Text("\(a.shifts.count) משמרות · \(fmtHM(a.minutes)) שעות · " + (rates.count > 1 ? "תעריף משתנה" : "\(fmtMoney(rates.first ?? model.rate(for: e)))/שעה"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(fmtMoney(a.pay)).fontWeight(.semibold).monospacedDigit()
                                        Text(a.shifts.isEmpty ? "" : a.allPaid ? "שולם ✓" : a.unpaidShifts.isEmpty ? "במשמרת עכשיו" : a.paidAgorot > 0 ? "נותר \(fmtMoney(a.unpaid))" : "לא שולם")
                                            .font(.caption).foregroundStyle(a.allPaid ? .green : .secondary)
                                    }
                                }.padding(.vertical, 8).padding(.horizontal, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain).focusEffectDisabled()
                            Divider()
                        }
                        HStack { Text("סה״כ החודש").fontWeight(.semibold); Spacer(); Text(fmtMoney(tPay)).font(.title3.weight(.bold)).monospacedDigit() }.padding(12)
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(20)
        }
        .navigationTitle("סיכום חודשי")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("ייצוא לאקסל…") { Exporter.excel(model) }
                    Button("שמירה כ-PDF…") { Exporter.savePDF(model) }
                    Button("הדפסה…") { Exporter.printReport(model) }
                } label: { Label("ייצוא", systemImage: "square.and.arrow.up") }
                .disabled(rows.allSatisfy { $0.1.shifts.isEmpty })
            }
        }
    }
    private func kpi(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(l).font(.caption).foregroundStyle(.secondary); Text(v).font(.title2.weight(.bold)).monospacedDigit() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
