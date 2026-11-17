import SwiftUI

/// Typed time entry ("830" → 08:30) plus a clock button that opens the haptic wheel.
struct TimeField: View {
    let label: String
    @Binding var value: String            // "HH:MM" (24h) or ""
    var focusRequest: Binding<Bool> = .constant(false)
    var pairedStart: String? = nil        // for יציאה: the clock-in time, used to pick AM/PM automatically
    var onFilled: () -> Void = {}         // 4 digits typed → e.g. jump from כניסה to יציאה
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var ampm = "AM"
    @State private var showWheel = false
    @State private var manualAP = false   // user pressed the AM/PM button → stop auto-picking
    @State private var auto = false       // value came from typing an ambiguous 1–12 hour
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
                    .onChange(of: text) { _, t in typing(t) }
                    .onChange(of: focusRequest.wrappedValue) { _, on in if on { focused = true; focusRequest.wrappedValue = false } }
                    .onChange(of: focused) { _, f in if !f { commit() } }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.red, lineWidth: invalid ? 1.5 : 0))
                    .accessibilityLabel(label)
                if model.twelve {
                    Button(ampm) { ampm = ampm == "AM" ? "PM" : "AM"; manualAP = true; commit() }
                        .buttonStyle(.bordered).controlSize(.small).help("החלפה בין AM ל-PM")
                }
                Button { showWheel = true } label: { Image(systemName: "clock") }
                    .help("בחירה בגלגלת")
                    .accessibilityLabel("בחירת שעת \(label) בגלגלת")
                    .popover(isPresented: $showWheel, arrowEdge: .bottom) {
                        TimeWheelPicker(title: "שעת \(label)", twelve: model.twelve, initial: value.isEmpty ? (label == "כניסה" ? "08:00" : "16:00") : value,
                                        pairedStart: pairedStart, autoInitial: value.isEmpty) {
                            auto = false; value = $0; showWheel = false      // picked on the wheel = explicit
                        } onCancel: { showWheel = false }
                        .environment(model)
                    }
            }
        }
        .onAppear { if value.isEmpty { ampm = label == "כניסה" ? "AM" : "PM" }; sync() }
        .onChange(of: value) { _, v in if v.isEmpty { manualAP = false; auto = false }; if !focused { sync() } }
        .onChange(of: pairedStart) { _, _ in repick() }
        .onChange(of: model.twelve) { _, _ in sync() }
    }

    private func sync() {
        invalid = false
        guard !value.isEmpty else { text = ""; return }
        guard let m = parseHM(value) else { text = value; return }   // never crash on an odd stored time
        let h = m / 60
        ampm = h < 12 ? "AM" : "PM"
        text = model.twelve ? "\(h % 12 == 0 ? 12 : h % 12):" + String(format: "%02d", m % 60) : value
    }
    /// Digits → "HH:MM". In AM/PM mode an ambiguous exit hour (1–12) gets the AM/PM that makes the shift shorter,
    /// unless the user set AM/PM by hand; a 24h hour (0 or 13–23) is taken as typed.
    private func resolve(_ digits: String) -> String? {
        guard model.twelve else { return parseTyped(digits) }
        let typedH = Int(digits.count <= 2 ? digits : String(digits.dropLast(2))) ?? 0
        if (1...12).contains(typedH), !manualAP, let start = pairedStart, !start.isEmpty {
            auto = true
            let m = Int(digits.count <= 2 ? "0" : String(digits.suffix(2))) ?? 0
            ampm = bestAmpm(start: start, hour: typedH, minute: m)
        } else if (1...12).contains(typedH) { auto = pairedStart != nil && !manualAP } else { auto = false }
        return parseTyped(digits, ampm: ampm)
    }
    /// Clock-in changed → re-pick the exit's AM/PM (only if it was typed without an explicit AM/PM).
    private func repick() {
        guard model.twelve, auto, !manualAP, let start = pairedStart, !start.isEmpty, !value.isEmpty else { return }
        let p = value.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return }
        ampm = bestAmpm(start: start, hour: p[0], minute: p[1])
        if let v = parseTyped(String(format: "%d%02d", p[0] % 12 == 0 ? 12 : p[0] % 12, p[1]), ampm: ampm) { value = v; sync() }
    }
    /// While typing: shows "830" as "8:30", and once four digits are in, saves and moves on.
    private func typing(_ t: String) {
        guard focused else { return }
        let d = String(t.filter { $0.isASCII && $0.isNumber }.prefix(4))
        let shown = d.count >= 3 ? "\(d.dropLast(2)):\(d.suffix(2))" : d
        if shown != t { text = shown; return }
        if d.count == 4, let v = resolve(d) {
            invalid = false; value = v
            onFilled()
        }
    }
    private func commit() {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        if digits.isEmpty { value = ""; invalid = false; return }
        guard let v = resolve(digits) else { invalid = true; return }
        invalid = false
        value = v
        sync()
    }
}
