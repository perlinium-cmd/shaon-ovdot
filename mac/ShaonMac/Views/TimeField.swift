import SwiftUI

/// Typed time entry ("830" → 08:30) plus a clock button that opens the haptic wheel.
struct TimeField: View {
    let label: String
    @Binding var value: String            // "HH:MM" (24h) or ""
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var ampm = "AM"
    @State private var showWheel = false
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("", text: $text, prompt: Text(model.twelve ? "8:00" : "08:00"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .frame(width: 86)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, f in if !f { commit() } }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.red, lineWidth: invalid ? 1.5 : 0))
                    .accessibilityLabel(label)
                if model.twelve {
                    Button(ampm) { ampm = ampm == "AM" ? "PM" : "AM"; commit() }
                        .buttonStyle(.bordered).controlSize(.small).help("החלפה בין AM ל-PM")
                }
                Button { showWheel = true } label: { Image(systemName: "clock") }
                    .help("בחירה בגלגלת")
                    .accessibilityLabel("בחירת שעת \(label) בגלגלת")
                    .popover(isPresented: $showWheel, arrowEdge: .bottom) {
                        TimeWheelPicker(title: "שעת \(label)", twelve: model.twelve, initial: value.isEmpty ? (label == "כניסה" ? "08:00" : "16:00") : value) {
                            value = $0; showWheel = false
                        } onCancel: { showWheel = false }
                        .environment(model)
                    }
            }
        }
        .onAppear(perform: sync)
        .onChange(of: value) { _, _ in if !focused { sync() } }
        .onChange(of: model.twelve) { _, _ in sync() }
    }

    private func sync() {
        invalid = false
        guard !value.isEmpty else { text = ""; return }
        let p = value.split(separator: ":").compactMap { Int($0) }
        ampm = p[0] < 12 ? "AM" : "PM"
        text = model.twelve ? "\(p[0] % 12 == 0 ? 12 : p[0] % 12):" + String(format: "%02d", p[1]) : value
    }
    private func commit() {
        let digits = text.filter(\.isNumber)
        if digits.isEmpty { value = ""; invalid = false; return }
        guard let v = parseTyped(digits, ampm: model.twelve ? ampm : nil) else { invalid = true; return }
        invalid = false
        value = v
        sync()
    }
}
