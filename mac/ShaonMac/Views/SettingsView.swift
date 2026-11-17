import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthService.self) private var auth: AuthService?
    @AppStorage("wheelSound") private var sound = true
    @AppStorage("hapticStrength") private var strength = Haptics.Strength.strong.rawValue
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("monthEndReminder") private var reminder = false
    @State private var launchAtLogin = LaunchAtLogin.isOn
    @State private var rate = ""
    @State private var shownRate: Double?   // what the field was filled with
    @State private var applyToMonth = true
    @State private var error: String?
    @State private var saving = false
    @State private var saved = false

    var body: some View {
        TabView {
            Form {
                TextField("תעריף שעתי כללי (₪)", text: $rate).onSubmit(saveRate)
                    .onChange(of: rate) { if parseRate(rate) != shownRate { error = nil; saved = false } }
                Text("חל על כל העובדות שאין להן תעריף אישי. תעריף אישי מגדירים ב\"עריכה\" בדף של העובדת.").font(.caption).foregroundStyle(.secondary)
                if !affected.isEmpty {
                    Toggle("לעדכן גם את \(affected.count == 1 ? "המשמרת" : "\(affected.count) המשמרות") של \(fmtMonth(model.month)) שעוד לא שולמו (של עובדות בתעריף הכללי)", isOn: $applyToMonth)
                }
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("שמירה", action: saveRate).buttonStyle(.borderedProminent).disabled(saving)
                    if saved { Label("נשמר", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                Section("מערכת") {
                    Toggle("הפעלה בכניסה למחשב", isOn: Binding(get: { launchAtLogin }, set: { launchAtLogin = $0; LaunchAtLogin.set($0) }))
                    Toggle("שעון בסרגל התפריטים", isOn: $showMenuBar)
                    Toggle("תזכורת בסוף החודש כשיש יתרה לתשלום", isOn: $reminder)
                        .onChange(of: reminder) { _, on in
                            if on { Task { if !(await Reminders.requestPermission()) { reminder = false } ; Reminders.update(model: model) } }
                            else { Reminders.update(model: model) }
                        }
                }
            }.tabItem { Label("כללי", systemImage: "gearshape") }

            Form {
                Picker("תצוגת שעה", selection: Binding(get: { model.twelve ? "12" : "24" }, set: { v in Task { await model.saveSettings { $0.timeFormat = v } } })) {
                    Text("24 שעות (14:30)").tag("24"); Text("AM/PM (2:30 PM)").tag("12")
                }.pickerStyle(.radioGroup)
            }.tabItem { Label("תצוגה", systemImage: "clock") }

            Form {
                Toggle("צליל גלגל שיניים", isOn: $sound)
                Picker("עוצמת רטט", selection: $strength) {
                    Text("רגיל").tag(Haptics.Strength.normal.rawValue); Text("חזק").tag(Haptics.Strength.strong.rawValue)
                }.pickerStyle(.segmented)
                Text("הרטט מורגש רק כשהאצבעות על הטראקפד.").font(.caption).foregroundStyle(.secondary)
            }.tabItem { Label("גלגלת", systemImage: "dial.medium") }

            Form {
                if let auth, case .signedIn(_, let name, let email) = auth.state {
                    LabeledContent("חשבון") { Text(name.isEmpty ? email : "\(name) · \(email)").textSelection(.enabled) }
                    Button("התנתקות", role: .destructive) { auth.signOut() }
                } else { Text("מצב הדגמה – הנתונים נשמרים רק בזיכרון").foregroundStyle(.secondary) }
            }.tabItem { Label("חשבון", systemImage: "person.crop.circle") }
        }
        .formStyle(.grouped).frame(width: 480, height: 360)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear(perform: fill)
        // Loaded after the window opened, or changed on another device: show it, unless it is being edited here
        // (otherwise "שמירה" would quietly put the old rate back).
        .onChange(of: model.defaultRate) { if parseRate(rate) == shownRate { fill() } }
    }
    private func fill() {
        shownRate = model.defaultRate
        rate = model.defaultRate.map(fmtNum) ?? ""
    }
    /// This month's unpaid shifts of employees on the general rate — only when the rate actually changes (same rule as the website).
    private var affected: [Shift] {
        guard let r = parseRate(rate), !r.isNaN, r != model.defaultRate else { return [] }
        return (model.shifts ?? []).filter { s in !s.isPaid && (model.emp(s.empId).map { $0.rate == nil } ?? false) }
    }
    private func saveRate() {
        guard !saving else { return }
        guard let r = parseRate(rate), !r.isNaN else { error = "צריך להזין תעריף תקין, לדוגמה 40"; return }
        error = nil; saved = false; saving = true
        let list = applyToMonth ? affected : []
        Task {
            if await model.saveSettings({ $0.defaultRate = r }) {
                await model.applyRate(r, to: list)
                shownRate = r; saved = true
                model.say("התעריף נשמר")
            } else {
                error = "התעריף לא נשמר. אם אין חיבור לאינטרנט, נסה שוב כשיש חיבור (צריך אותו כדי שמשמרות קודמות יישארו בתעריף שבו עבדו)."
            }
            saving = false
        }
    }
}
