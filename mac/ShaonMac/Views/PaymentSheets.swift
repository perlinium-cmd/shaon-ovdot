import SwiftUI

/// Pay one or more shifts at once: choose how and when. One payment record, the exact sum of the shifts (AppModel.markPaid).
struct PaySheet: View {
    let emp: Employee
    let shifts: [Shift]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var method = ""
    @State private var date = Date()
    @State private var saving = false

    var body: some View {
        let todo = shifts.filter { !$0.isPaid && !$0.isOpen }
        let sum = Double(todo.reduce(0) { $0 + shiftPayAgorot($1, emp, defaultRate: model.defaultRate) }) / 100
        Form {
            Text("תשלום ל\(emp.name)").font(.title3.weight(.semibold))
            LabeledContent(nShifts(todo.count)) { Text(fmtMoney(sum)).font(.title3.bold()).monospacedDigit() }
            Picker("איך שולם?", selection: $method) { ForEach(AppModel.payMethods, id: \.self) { Text($0) } }
            DatePicker("תאריך התשלום", selection: $date, displayedComponents: .date)
            HStack {
                Spacer()
                Button("ביטול", role: .cancel) { dismiss() }
                Button {
                    saving = true
                    Task { await model.markPaid(todo.map(\.id), method: method, date: dateStr(date)); dismiss() }
                } label: { Label("סימון כשולם", systemImage: "checkmark") }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(todo.isEmpty || saving)
            }
        }
        .formStyle(.grouped).frame(width: 420).padding()
        .onAppear { method = AppModel.payMethods.contains(model.payMethod) ? model.payMethod : AppModel.payMethods[0] }
    }
}

/// All payments of one employee (every month), with edit and delete — same as the website.
struct PaymentsSheet: View {
    let emp: Employee
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var payments: [Payment] = []
    @State private var unsub: (() -> Void)?
    @State private var editing: Payment?
    @State private var askDelete: Payment?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("תשלומים ל\(emp.name)").font(.title3.weight(.semibold)); Spacer(); Button("סגירה") { dismiss() }.keyboardShortcut(.cancelAction) }
            if payments.isEmpty { ContentUnavailableView("עוד לא שולם כלום", systemImage: "banknote") }
            else {
                List(payments.sorted { ($0.date, $0.createdAt ?? 0) > ($1.date, $1.createdAt ?? 0) }) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(fmtMoney(p.amount)).fontWeight(.semibold).monospacedDigit()
                            Text("\(p.method) · \(fmtDayMonth(p.date))/\(parseDate(p.date).formatted(.dateTime.year())) · \(nShifts(p.shiftIds?.count ?? 0))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("עריכה") { editing = p }
                        Button("מחיקה", role: .destructive) { askDelete = p }
                    }
                }
            }
        }
        .padding(20).frame(width: 520, height: 380)
        .onAppear { unsub = model.store.watchPayments(empId: emp.id) { payments = $0 } }
        .onDisappear { unsub?() }
        .sheet(item: $editing) { p in EditPaymentSheet(payment: p) }
        .confirmationDialog("למחוק את התשלום של \(fmtMoney(askDelete?.amount ?? 0))?", isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } })) {
            Button("מחיקת התשלום", role: .destructive) { if let p = askDelete { Task { await model.deletePayment(p) } } }
        } message: { Text("המשמרות שלו יסומנו כלא שולמו. אפשר לבטל עם ⌘Z.") }
    }
}

/// Change how and when a payment was made (its amount and shifts stay).
struct EditPaymentSheet: View {
    let payment: Payment
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var method = ""
    @State private var date = Date()
    var body: some View {
        Form {
            Text("תשלום של \(fmtMoney(payment.amount))").font(.title3.weight(.semibold))
            Picker("איך שולם?", selection: $method) {
                ForEach(AppModel.payMethods + (AppModel.payMethods.contains(payment.method) ? [] : [payment.method]), id: \.self) { Text($0) }
            }
            DatePicker("תאריך התשלום", selection: $date, displayedComponents: .date)
            HStack {
                Spacer()
                Button("ביטול", role: .cancel) { dismiss() }
                Button("שמירה") { Task { await model.updatePayment(payment, method: method, date: dateStr(date)); dismiss() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped).frame(width: 400).padding()
        .onAppear { method = payment.method; date = parseDate(payment.date) }
    }
}
