import SwiftUI

/// Add a shift (shift == nil) or edit one. Used in the employee page and in the inspector.
struct ShiftForm: View {
    let emp: Employee
    var shift: Shift? = nil
    var onDone: () -> Void = {}
    @Environment(AppModel.self) private var model
    @State private var date = Date()
    @State private var tin = ""
    @State private var tout = ""
    @State private var specialOn = false
    @State private var spRate = ""
    @State private var spPart = false
    @State private var spHours = ""
    @State private var error: String?
    @State private var loaded = false

    private var dateS: String { dateStr(date) }
    private var last: (String, String)? {
        model.shifts(of: emp.id).first(where: { $0.id != shift?.id }).map { ($0.in, $0.out) }
    }
    private var draft: Shift? {
        guard !tin.isEmpty, !tout.isEmpty, tin != tout else { return nil }
        let r = parseRate(spRate)
        let h = spPart ? parseRate(spHours) : nil
        let ok = specialOn && r != nil && !(r!.isNaN) && !(spPart && (h == nil || h!.isNaN))
        return Shift(id: shift?.id ?? "", empId: emp.id, date: dateS, month: String(dateS.prefix(7)), in: tin, out: tout,
                     rate: shift?.rate ?? model.rate(for: emp), special: ok ? Special(rate: r, hours: h) : nil, paid: shift?.paid ?? false)
    }
    private var dup: [Shift] { model.shifts(of: emp.id).filter { $0.date == dateS && $0.id != shift?.id } }

    var body: some View {
        Form {
            Section {
                HStack {
                    DatePicker("תאריך", selection: $date, displayedComponents: .date).labelsHidden()
                    Button("היום") { date = .now }.controlSize(.small)
                    Button("אתמול") { date = gregorian.date(byAdding: .day, value: -1, to: .now)! }.controlSize(.small)
                }
                HStack(alignment: .bottom, spacing: 16) {
                    TimeField(label: "כניסה", value: $tin)
                    TimeField(label: "יציאה", value: $tout)
                    if shift == nil, let last, !(tin == last.0 && tout == last.1) {
                        Button { tin = last.0; tout = last.1 } label: { Label("כמו בפעם הקודמת: \(model.fmt(last.0))–\(model.fmt(last.1))", systemImage: "repeat") }
                            .controlSize(.small)
                    }
                }
                Toggle("תעריף מיוחד למשמרת (חג, שבת…)", isOn: $specialOn)
                if specialOn {
                    HStack {
                        TextField("סכום לשעה", text: $spRate).frame(width: 110)
                        Text("₪")
                        Picker("", selection: $spPart) { Text("כל המשמרת").tag(false); Text("חלק מהשעות").tag(true) }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                        if spPart { TextField("כמה שעות", text: $spHours).frame(width: 90) }
                    }
                }
            }
            if !dup.isEmpty {
                Label("כבר רשומה משמרת ב-\(fmtDayMonth(dateS)): " + dup.map { $0.isOpen ? "\(model.fmt($0.in)) (עדיין במשמרת)" : "\(model.fmt($0.in))–\(model.fmt($0.out))" }.joined(separator: ", "), systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange).font(.callout)
            }
            HStack {
                if let d = draft {
                    let min = shiftMinutes(d.in, d.out)
                    VStack(alignment: .leading) {
                        Text("\(fmtHM(min)) שעות").font(.title3.weight(.semibold)).monospacedDigit()
                        if isOvernight(d.in, d.out) { Text("משמרת לילה – היציאה למחרת").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(fmtMoney(shiftPay(d, emp, defaultRate: model.defaultRate))).font(.title2.weight(.bold)).foregroundStyle(.tint).monospacedDigit()
                } else {
                    Text("בחר שעת כניסה ויציאה").foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                if shift != nil { Button("ביטול", role: .cancel, action: onDone) }
                Button(shift == nil ? "שמירה" : "עדכון") { Task { await save() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: shift?.id) { _, _ in loaded = false; load() }
        .onChange(of: tin) { _, _ in error = nil }
        .onChange(of: tout) { _, _ in error = nil }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let s = shift {
            date = parseDate(s.date); tin = s.in; tout = s.out
            specialOn = s.special?.rate != nil
            spRate = s.special?.rate.map { String($0) } ?? ""
            spPart = s.special?.hours != nil
            spHours = s.special?.hours.map { String($0) } ?? ""
        } else {
            date = model.month == currentMonth() ? .now : parseDate(model.month + "-01")
            tin = ""; tout = ""; specialOn = false; spRate = ""; spPart = false; spHours = ""
        }
        error = nil
    }

    private func save() async {
        if tin.isEmpty { error = "צריך להזין שעת כניסה"; return }
        if tout.isEmpty { error = "צריך להזין שעת יציאה"; return }
        if tin == tout { error = "שעת היציאה זהה לשעת הכניסה"; return }
        var special: Special?
        if specialOn {
            let r = parseRate(spRate)
            if r == nil || r!.isNaN { error = "צריך להזין סכום לשעה לתעריף המיוחד"; return }
            var h: Double?
            if spPart {
                let hh = parseRate(spHours)
                if hh == nil || hh!.isNaN || hh! <= 0 { error = "צריך להזין כמה שעות בתעריף המיוחד"; return }
                h = hh
            }
            special = Special(rate: r, hours: h)
        }
        if var s = shift {
            s.date = dateS; s.month = String(dateS.prefix(7)); s.in = tin; s.out = tout; s.special = special
            if s.isOpen { s.open = false }   // the manager closed a running phone shift
            await model.updateShift(s)
            onDone()
        } else {
            await model.addShift(Shift(empId: emp.id, date: dateS, month: String(dateS.prefix(7)), in: tin, out: tout,
                                       rate: model.rate(for: emp), special: special, paid: false))
            if String(dateS.prefix(7)) != model.month { model.month = String(dateS.prefix(7)) }
            tin = ""; tout = ""; specialOn = false; spRate = ""; spHours = ""
        }
    }
}
