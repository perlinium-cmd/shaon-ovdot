import SwiftUI

/// The clock in the menu bar: month at a glance + quick shift entry without opening the window.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var empId = ""
    @State private var tin = ""
    @State private var tout = ""

    var body: some View {
        let agg = model.agg
        let emps = (model.employees ?? []).filter(\.isActive)
        let tPay = agg.values.reduce(0) { $0 + $1.pay }, tPaid = agg.values.reduce(0) { $0 + $1.paidPay }
        let tMin = agg.values.reduce(0) { $0 + $1.minutes }
        VStack(alignment: .leading, spacing: 12) {
            Text(fmtMonth(model.month)).font(.headline)
            HStack(spacing: 16) {
                stat("נותר לתשלום", fmtMoney(tPay - tPaid)); stat("שולם", fmtMoney(tPaid)); stat("שעות", fmtHM(tMin))
            }
            Divider()
            if emps.isEmpty { Text("אין עובדות עדיין").foregroundStyle(.secondary) }
            else {
                Text("משמרת מהירה להיום").font(.subheadline.weight(.semibold))
                Picker("עובדת", selection: $empId) { ForEach(emps) { Text($0.name).tag($0.id) } }.labelsHidden()
                HStack(alignment: .bottom, spacing: 12) {
                    TimeField(label: "כניסה", value: $tin)
                    TimeField(label: "יציאה", value: $tout)
                }
                Button("שמירה") { Task { await save(emps) } }
                    .buttonStyle(.borderedProminent).disabled(tin.isEmpty || tout.isEmpty || tin == tout)
            }
            Divider()
            HStack {
                Button("פתיחת האפליקציה") { NSApp.activate(ignoringOtherApps: true); if NSApp.windows.filter(\.isVisible).isEmpty { openWindow(id: "main") } }
                Spacer()
                Button("יציאה") { NSApp.terminate(nil) }
            }
        }
        .padding(16).frame(width: 320)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { if empId.isEmpty { empId = emps.first?.id ?? "" } }
    }

    private func stat(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading) { Text(l).font(.caption).foregroundStyle(.secondary); Text(v).font(.callout.weight(.semibold)).monospacedDigit() }
    }
    private func save(_ emps: [Employee]) async {
        guard let e = emps.first(where: { $0.id == empId }) ?? emps.first else { return }
        let d = todayStr()
        // Not saved: keep what was typed (the message says why).
        guard await model.addShift(Shift(empId: e.id, date: d, month: String(d.prefix(7)), in: tin, out: tout, rate: model.rate(for: e), special: nil, paid: false)) else { return }
        tin = ""; tout = ""
    }
}
