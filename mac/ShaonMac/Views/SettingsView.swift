import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthService.self) private var auth: AuthService?
    @AppStorage("wheelSound") private var sound = true
    @AppStorage("hapticStrength") private var strength = Haptics.Strength.strong.rawValue
    @State private var rate = ""
    @State private var error: String?

    var body: some View {
        TabView {
            Form {
                TextField("תעריף שעתי כללי (₪)", text: $rate).onSubmit(saveRate)
                Text("חל על כל העובדות שאין להן תעריף אישי.").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                Button("שמירה", action: saveRate).buttonStyle(.borderedProminent)
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
        .formStyle(.grouped).frame(width: 460, height: 260)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { rate = model.defaultRate.map { String($0) } ?? "" }
    }
    private func saveRate() {
        guard let r = parseRate(rate), !r.isNaN else { error = "צריך להזין תעריף תקין"; return }
        error = nil
        Task { if await model.saveSettings({ $0.defaultRate = r }) { model.say("התעריף נשמר") } }
    }
}
