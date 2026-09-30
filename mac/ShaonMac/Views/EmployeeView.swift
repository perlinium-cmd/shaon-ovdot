import SwiftUI

struct EmployeeView: View {
    let empId: String
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\Shift.date, order: .reverse)]
    @State private var inspectorOpen = false
    @State private var editingEmployee = false
    @State private var confirmDelete: [String]?

    var body: some View {
        if let emp = model.emp(empId) {
            let shifts = model.shifts(of: empId).sorted(using: sortOrder)
            let a = model.agg[empId] ?? Agg()
            VStack(spacing: 0) {
                header(emp)
                ShiftForm(emp: emp).frame(height: 300)
                Divider()
                if shifts.isEmpty {
                    ContentUnavailableView("אין משמרות ב\(fmtMonthName(model.month))", systemImage: "clock",
                                           description: Text("הוסף משמרת בטופס למעלה."))
                } else {
                    table(shifts, emp)
                }
                Divider()
                totals(a)
            }
            .inspector(isPresented: $inspectorOpen) {
                if let s = shifts.first(where: { selection.count == 1 && selection.contains($0.id) }) {
                    ShiftForm(emp: emp, shift: s) { inspectorOpen = false }
                        .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
                }
            }
            .onChange(of: selection) { _, new in inspectorOpen = new.count == 1 }
            .sheet(isPresented: $editingEmployee) { EmployeeEditor(emp: emp) }
            .confirmationDialog("למחוק \(confirmDelete?.count ?? 0) משמרות?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
                Button("מחיקה", role: .destructive) { let ids = confirmDelete ?? []; selection = []; Task { await model.deleteShifts(ids) } }
            } message: { Text("אפשר לבטל עם ⌘Z.") }
            .navigationTitle(emp.name)
        } else {
            ContentUnavailableView("העובדת לא נמצאה", systemImage: "person.slash")
        }
    }

    private func header(_ emp: Employee) -> some View {
        HStack(spacing: 12) {
            Avatar(name: emp.name, size: 44)
            VStack(alignment: .leading) {
                Text(emp.name).font(.title2.weight(.bold))
                Text("\(fmtMoney(model.rate(for: emp)))/שעה · \(emp.rate != nil ? "אישי" : "כללי")" + (emp.isActive ? "" : " · בארכיון"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { editingEmployee = true } label: { Label("עריכה", systemImage: "pencil") }
        }
        .padding([.horizontal, .top], 16).padding(.bottom, 4)
    }

    private func table(_ shifts: [Shift], _ emp: Employee) -> some View {
        Table(shifts, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("תאריך", value: \.date) { s in Text("\(fmtDayMonth(s.date)) · \(fmtWeekday(s.date))").monospacedDigit() }
            TableColumn("שעות") { s in
                HStack(spacing: 4) {
                    Text("\(model.fmt(s.in)) – \(model.fmt(s.out))").monospacedDigit()
                    if isOvernight(s.in, s.out) { Image(systemName: "moon.fill").foregroundStyle(.indigo).help("משמרת לילה") }
                    if s.special?.rate != nil { Image(systemName: "star.fill").foregroundStyle(.orange).help("תעריף מיוחד") }
                }
            }
            TableColumn("סה״כ") { s in Text(fmtHM(shiftMinutes(s.in, s.out))).monospacedDigit() }.width(60)
            TableColumn("סכום") { s in Text(fmtMoney(model.pay(s))).monospacedDigit().fontWeight(.medium) }.width(90)
            TableColumn("שולם") { s in
                Toggle("שולם", isOn: Binding(get: { s.isPaid }, set: { v in Task { await model.setPaid([s.id], paid: v) } }))
                    .labelsHidden().toggleStyle(.checkbox)
            }.width(60)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                Button("סימון כשולם") { Task { await model.setPaid(Array(ids), paid: true) } }
                Button("סימון כלא שולם") { Task { await model.setPaid(Array(ids), paid: false) } }
                Divider()
                Button("מחיקה", role: .destructive) { confirmDelete = Array(ids) }
            }
        } primaryAction: { ids in selection = ids; inspectorOpen = ids.count == 1 }
        .onDeleteCommand { if !selection.isEmpty { confirmDelete = Array(selection) } }
    }

    private func totals(_ a: Agg) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading) {
                Text(a.paidPay > 0 ? (a.unpaid <= 0 ? "שולם הכל ✓" : "נותר לתשלום · מתוך \(fmtMoney(a.pay))") : "סה״כ \(fmtMonthName(model.month))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(fmtMoney(a.paidPay > 0 && a.unpaid > 0 ? a.unpaid : a.pay)).font(.title2.weight(.bold)).monospacedDigit()
            }
            Spacer()
            stat("שעות", fmtHM(a.minutes))
            stat("משמרות", "\(a.shifts.count)")
            if a.shifts.contains(where: { !$0.isPaid }) {
                Button { let ids = a.shifts.filter { !$0.isPaid }.map(\.id); Task { await model.setPaid(ids, paid: true) } } label: { Label("סימון הכל כשולם", systemImage: "checkmark") }
            }
        }
        .padding(16)
    }
    private func stat(_ l: String, _ v: String) -> some View {
        VStack(alignment: .trailing) { Text(l).font(.caption).foregroundStyle(.secondary); Text(v).font(.title3.weight(.semibold)).monospacedDigit() }
    }
}

struct EmployeeEditor: View {
    let emp: Employee?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var rate = ""
    @State private var error: String?
    @State private var askDelete = false

    var body: some View {
        Form {
            Text(emp == nil ? "עובדת חדשה" : "עריכת פרטים").font(.title3.weight(.semibold))
            TextField("שם", text: $name)
            TextField("תעריף שעתי אישי (לא חובה)", text: $rate, prompt: Text("\(model.defaultRate ?? 0)"))
            Text("השאר ריק כדי להשתמש בתעריף הכללי (\(fmtMoney(model.defaultRate ?? 0)) לשעה).").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if let emp {
                    Button(emp.isActive ? "העברה לארכיון" : "החזרה לרשימה") {
                        var e = emp; e.active = !emp.isActive
                        Task { await model.updateEmployee(e); dismiss() }
                    }
                    Button("מחיקה לצמיתות", role: .destructive) { askDelete = true }
                }
                Spacer()
                Button("ביטול", role: .cancel) { dismiss() }
                Button(emp == nil ? "הוספה" : "שמירה") { Task { await save() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped).frame(width: 440).padding()
        .onAppear { name = emp?.name ?? ""; rate = emp?.rate.map { String($0) } ?? "" }
        .confirmationDialog("למחוק את \(emp?.name ?? "")?", isPresented: $askDelete) {
            Button("מחיקה לצמיתות", role: .destructive) { if let emp { Task { await model.deleteEmployee(emp); dismiss() } } }
        } message: { Text("כל המשמרות שלה יימחקו. אפשר במקום זה להעביר לארכיון.") }
    }

    private func save() async {
        let n = name.trimmingCharacters(in: .whitespaces)
        let r = parseRate(rate)
        if n.isEmpty { error = "צריך להזין שם"; return }
        if let r, r.isNaN { error = "תעריף לא תקין"; return }
        if var emp { emp.name = n; emp.rate = r; await model.updateEmployee(emp) }
        else { _ = await model.addEmployee(name: n, rate: r) }
        dismiss()
    }
}
