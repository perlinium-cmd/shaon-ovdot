import SwiftUI

/// Transparent AppKit view on top of a wheel column. It reads raw scroll events so the trackpad
/// haptic fires synchronously inside the event handler — the only moment macOS plays it at full strength.
struct ScrollTickView: NSViewRepresentable {
    var onSteps: (_ steps: Int, _ fingersDown: Bool) -> Void
    var onClickRow: (_ rowOffsetFromCenter: Int) -> Void
    let rowH: CGFloat

    func makeNSView(context: Context) -> NSView {
        let v = TickNSView()
        v.owner = self
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { (v as? TickNSView)?.owner = self }

    final class TickNSView: NSView {
        var owner: ScrollTickView?
        private var acc: CGFloat = 0
        private let stepPx: CGFloat = 14           // pixels of finger travel per tooth
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { false }

        override func scrollWheel(with e: NSEvent) {
            if e.phase == .began || e.phase == .mayBegin { acc = 0 }
            // Mouse wheels report line deltas; treat one notch as one tooth.
            let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * stepPx
            acc -= dy   // content moves up (fingers up) → later rows
            let steps = Int(acc / stepPx)
            if steps != 0 {
                acc -= CGFloat(steps) * stepPx
                let fingersDown = e.momentumPhase.isEmpty
                owner?.onSteps(steps, fingersDown)
            }
            if e.phase == .ended || e.phase == .cancelled { acc = 0 }
        }
        override func mouseDown(with e: NSEvent) {
            let y = convert(e.locationInWindow, from: nil).y
            owner?.onClickRow(Int((y / (owner?.rowH ?? 40)).rounded(.down)) - 2)
        }
    }
}

/// One scrolling column that snaps to rows; every row change = a trackpad tick + gear click.
struct WheelColumn: View {
    let items: [String]
    @Binding var index: Int
    var width: CGFloat = 72
    /// Rows that get the stronger "accent" tick (e.g. minute 00).
    var accentRows: Set<Int> = []
    @AppStorage("wheelSound") private var soundOn = true
    @AppStorage("hapticStrength") private var strength = Haptics.Strength.strong.rawValue

    static let rowH: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Text(items[i])
                    .font(.system(size: 22, weight: i == index ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .scaleEffect(i == index ? 1.18 : 1)
                    .foregroundStyle(i == index ? Color.primary : Color.secondary.opacity(0.7))
                    .frame(width: width, height: Self.rowH)
            }
        }
        .offset(y: Self.rowH * CGFloat(2 - index) + Self.rowH * CGFloat(items.count - 5) / 2)
        .animation(.snappy(duration: 0.14), value: index)
        .frame(width: width, height: Self.rowH * 5)
        .clipped()
        .mask(LinearGradient(colors: [.clear, .black, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
        .overlay {
            ScrollTickView(onSteps: { steps, fingersDown in move(steps, haptic: fingersDown) },
                           onClickRow: { move($0, haptic: true) }, rowH: Self.rowH)
        }
        .focusable()
        .onKeyPress(.upArrow) { move(-1, haptic: true); return .handled }
        .onKeyPress(.downArrow) { move(1, haptic: true); return .handled }
        .accessibilityAdjustableAction { dir in move(dir == .increment ? 1 : -1, haptic: false) }
    }

    /// Moves one tooth at a time so a fast flick gives one tick per number passed.
    private func move(_ steps: Int, haptic: Bool) {
        guard steps != 0 else { return }
        let target = max(0, min(items.count - 1, index + steps))
        guard target != index else {
            if haptic { Haptics.tick(accent: true, strength: .strong) }   // hit the end of the list
            return
        }
        index = target
        let edge = target == 0 || target == items.count - 1
        if haptic { Haptics.tick(accent: edge || accentRows.contains(target), strength: Haptics.Strength(rawValue: strength) ?? .strong) }
        if soundOn { GearClick.shared.click() }
    }
}

/// Popover time picker: hours, minutes (and AM/PM). Value is a 24h "HH:MM" string.
struct TimeWheelPicker: View {
    let title: String
    let twelve: Bool
    let initial: String
    /// Exit wheel in AM/PM mode: the clock-in time; AM/PM then follows hour/minute (shorter shift) until the user picks it.
    var pairedStart: String? = nil
    var autoInitial = false
    var onDone: (String) -> Void
    var onCancel: () -> Void

    @State private var h = 0
    @State private var m = 0
    @State private var pm = 0
    @State private var apTouched = false
    @State private var lastAutoPm: Int?

    private var hours: [String] {
        if twelve { return ["12"] + (1...11).map { String($0) } }
        return (0..<24).map { String(format: "%02d", $0) }
    }
    private var value: String {
        let hh = twelve ? (h % 12) + (pm == 1 ? 12 : 0) : h
        return String(format: "%02d:%02d", hh, m)
    }

    private func autoAp() {
        guard twelve, let start = pairedStart, !start.isEmpty, !apTouched else { return }
        let want = bestAmpm(start: start, hour: h == 0 ? 12 : h, minute: m) == "PM" ? 1 : 0
        if want != pm { lastAutoPm = want; pm = want }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(fmtTime(value, twelve: twelve)).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(.tint)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.tint.opacity(0.12)).frame(height: WheelColumn.rowH)
                HStack(spacing: 4) {
                    WheelColumn(items: hours, index: $h)
                        .onChange(of: h) { _, _ in autoAp() }
                    Text(":").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                    WheelColumn(items: (0..<60).map { String(format: "%02d", $0) }, index: $m, accentRows: [0, 15, 30, 45])
                        .onChange(of: m) { _, _ in autoAp() }
                    if twelve {
                        WheelColumn(items: ["AM", "PM"], index: $pm, width: 56)
                            .onChange(of: pm) { _, new in if new != lastAutoPm { apTouched = true } }   // changed by the user
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            Text("גוללים עם שתי אצבעות, או ↑↓ במקלדת").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("ביטול", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("אישור") { onDone(value) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear {
            let p = initial.split(separator: ":").compactMap { Int($0) }
            let hh = p.count == 2 ? p[0] : 8
            m = p.count == 2 ? p[1] : 0
            h = twelve ? hh % 12 : hh
            pm = hh < 12 ? 0 : 1
            if autoInitial { autoAp() }
        }
    }
}
