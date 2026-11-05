import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - "At work now" banner

/// Shown above every page while someone is clocked in from her phone.
struct LiveBanner: View {
    @Environment(AppModel.self) private var model
    var onOpen: (String) -> Void = { _ in }

    var body: some View {
        if !model.openShifts.isEmpty {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                VStack(spacing: 6) {
                    ForEach(model.openShifts.sorted { ($0.inAt ?? 0) < ($1.inAt ?? 0) }) { s in
                        let name = model.emp(s.empId)?.name ?? "עובדת"
                        let mins = s.runningMinutes(now: ctx.date) ?? 0
                        Button { onOpen(s.empId) } label: {
                            HStack(spacing: 10) {
                                Circle().fill(.green).frame(width: 9, height: 9)
                                Text("בעבודה עכשיו").font(.callout.weight(.semibold)).foregroundStyle(.green)
                                Avatar(name: name, size: 22)
                                Text(name).fontWeight(.semibold)
                                Text("מאז \(model.fmt(s.in))").foregroundStyle(.secondary)
                                if mins >= 12 * 60 {
                                    Label("פתוחה יותר מ-12 שעות. אולי שכחה ללחוץ יציאה?", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange).font(.callout)
                                }
                                Spacer()
                                Text(fmtHM(mins)).font(.title3.weight(.bold)).monospacedDigit()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("פתיחת הדף של \(name)")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Requests inbox

struct RequestsView: View {
    @Environment(AppModel.self) private var model
    var onOpen: (String) -> Void = { _ in }
    @State private var busy: String?
    @State private var newIds: Set<String> = []   // unseen when shown, so they stay highlighted while the page is open

    var body: some View {
        let pending = model.pendingRequests
        let decided = model.requests.filter { !$0.isPending }.sorted { ($0.decidedAt ?? $0.createdAt ?? 0) > ($1.decidedAt ?? $1.createdAt ?? 0) }.prefix(20)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("בקשות מהטלפון").font(.title2.weight(.bold))
                if pending.isEmpty {
                    ContentUnavailableView("אין בקשות שמחכות לך", systemImage: "checkmark.circle",
                                           description: Text("כשעובדת תבקש לתקן שעה או להוסיף משמרת, הבקשה תופיע כאן."))
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    ForEach(pending) { r in card(r) }
                }
                if !model.notices.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("עדכונים מהטלפון").font(.headline)
                        Text("שעות שהעובדות הזינו או שינו בעצמן באותו יום. הן נשמרו בלי אישור (עד שני שינויים בכל משמרת, מהשלישי צריך את האישור שלך). אם משהו לא נכון, אפשר לתקן בדף של העובדת.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                    ForEach(model.notices.prefix(40)) { n in noticeRow(n) }
                }
                if !decided.isEmpty {
                    Text("בקשות שטופלו לאחרונה").font(.headline).padding(.top, 12)
                    ForEach(Array(decided)) { r in decidedRow(r) }
                }
            }
            .padding(20).frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("בקשות ועדכונים")
        .task(id: model.unseenNotices.map(\.id)) {   // looking at the page marks the updates as read
            let ids = model.unseenNotices.map(\.id)
            guard !ids.isEmpty else { return }
            newIds.formUnion(ids)
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { await model.markNoticesSeen() }
        }
    }

    private func noticeRow(_ n: Notice) -> some View {
        let name = model.emp(n.empId)?.name ?? "עובדת"
        let d = model.describe(n)
        let isNew = newIds.contains(n.id) || !n.isSeen
        return Button {
            model.month = String(n.date.prefix(7))
            onOpen(n.empId)
        } label: {
            HStack(spacing: 10) {
                Circle().fill(isNew ? Color.accentColor : .clear).frame(width: 8, height: 8)
                Avatar(name: name, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title).fontWeight(isNew ? .semibold : .regular)
                    Text(d.detail).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if let t = n.createdAt { Text(when(t)).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(isNew ? Color.accentColor.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("פתיחת הדף של \(name)")
    }

    /// "14:05" for today, "5/11 14:05" otherwise.
    private func when(_ ms: Double) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000), day = dateStr(date)
        let hm = String(format: "%02d:%02d", gregorian.component(.hour, from: date), gregorian.component(.minute, from: date))
        return day == todayStr() ? model.fmt(hm) : "\(fmtDayMonth(day)) \(model.fmt(hm))"
    }

    private func card(_ r: ShiftRequest) -> some View {
        let name = model.emp(r.empId)?.name ?? "עובדת"
        let old = model.shift(r.shiftId)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Avatar(name: name, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.type == "add" ? "\(name) מבקשת להוסיף משמרת" : "\(name) מבקשת לתקן משמרת").font(.headline)
                    Text("\(fmtWeekday(r.date)) \(fmtDayMonth(r.date))").foregroundStyle(.secondary)
                }
                Spacer()
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                if r.type == "fix" {
                    GridRow {
                        Text("רשום עכשיו").foregroundStyle(.secondary)
                        if let old { Text(old.isOpen ? "\(model.fmt(old.in)) – עדיין במשמרת" : "\(model.fmt(old.in)) – \(model.fmt(old.out))").monospacedDigit() }
                        else { Text("לא בחודש המוצג").foregroundStyle(.secondary) }
                    }
                }
                GridRow {
                    Text("מבוקש").foregroundStyle(.secondary)
                    Text(r.out.isEmpty ? "כניסה ב-\(model.fmt(r.in)) (המשמרת עדיין פעילה)" : "\(model.fmt(r.in)) – \(model.fmt(r.out)) · \(fmtHM(shiftMinutes(r.in, r.out))) שעות")
                        .monospacedDigit().fontWeight(.semibold)
                }
                if let n = r.note, !n.isEmpty {
                    GridRow { Text("הערה").foregroundStyle(.secondary); Text(n) }
                }
            }
            if old?.isPaid == true {
                Label("המשמרת הזו כבר סומנה כשולמה. כדי לאשר, בטל קודם את סימון התשלום.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            HStack {
                Spacer()
                Button("דחייה") { act(r, false) }.disabled(busy != nil)
                Button("אישור") { act(r, true) }.buttonStyle(.borderedProminent).disabled(busy != nil || old?.isPaid == true)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }

    private func decidedRow(_ r: ShiftRequest) -> some View {
        let (label, color): (String, Color) = switch r.status {
        case "approved": ("אושרה", .green)
        case "rejected": ("נדחתה", .red)
        default: ("בוטלה ע״י העובדת", .secondary)
        }
        return HStack {
            Text(model.emp(r.empId)?.name ?? "עובדת")
            Text("\(fmtDayMonth(r.date)) · \(r.type == "add" ? "הוספה" : "תיקון") \(model.fmt(r.in))\(r.out.isEmpty ? "" : "–" + model.fmt(r.out))")
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Text(label).font(.callout.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.vertical, 4)
    }

    private func act(_ r: ShiftRequest, _ approve: Bool) {
        busy = r.id
        Task { await model.decide(r, approve: approve); busy = nil }
    }
}

// MARK: - Connected phones

struct PhonesView: View {
    @Environment(AppModel.self) private var model
    @State private var pairingFor: Employee?
    @State private var confirm: Device?

    var body: some View {
        List {
            Section {
                Text("כל עובדת מחברת את הטלפון שלה פעם אחת. אחרי זה הוא נשאר מחובר תמיד, גם אחרי התקנה מחדש. ניתוק כאן חוסם אותו מיד.")
                    .foregroundStyle(.secondary)
            }
            ForEach((model.employees ?? []).filter(\.isActive)) { e in
                Section {
                    let ds = model.devices(of: e.id)
                    if ds.isEmpty {
                        Text("אין טלפון מחובר").foregroundStyle(.secondary)
                    }
                    ForEach(ds) { d in
                        HStack {
                            Image(systemName: "iphone.gen3").foregroundStyle(.tint)
                            Text(d.model ?? "טלפון")
                            if let p = d.pairedAt {
                                Text("חובר \(fmtDate(p))").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("ניתוק", role: .destructive) { confirm = d }
                        }
                    }
                } header: {
                    HStack {
                        Avatar(name: e.name, size: 22)
                        Text(e.name).font(.headline)
                        Spacer()
                        Button { pairingFor = e } label: { Label("חיבור טלפון", systemImage: "qrcode") }
                    }
                }
            }
        }
        .navigationTitle("טלפונים מחוברים")
        .sheet(item: $pairingFor) { e in PairSheet(emp: e) }
        .onAppear {   // `-pair <empId>` opens the pairing window directly (used for screenshots of the demo)
            if model.store.isDemo, let id = UserDefaults.standard.string(forKey: "pair") { pairingFor = model.emp(id) }
        }
        .confirmationDialog("לנתק את הטלפון של \(model.emp(confirm?.empId ?? "")?.name ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("ניתוק", role: .destructive) { if let d = confirm { Task { await model.disconnect(d) } } }
        } message: { Text("הטלפון יפסיק מיד לראות ולרשום שעות. המשמרות שכבר נרשמו נשארות. אפשר לחבר אותו שוב בקוד חדש.") }
    }

    private func fmtDate(_ ms: Double) -> String { fmtDayMonth(dateStr(Date(timeIntervalSince1970: ms / 1000))) }
}

/// Shows a QR code + typed code for 10 minutes, and closes by itself once the phone connected.
struct PairSheet: View {
    let emp: Employee
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pairing: Pairing?
    @State private var done = false
    @State private var unwatch: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text("חיבור הטלפון של \(emp.name)").font(.title2.weight(.bold))
            if done {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
                Text("הטלפון מחובר!").font(.title3.weight(.semibold))
            } else if let p = pairing {
                Text("באפליקציה בטלפון: \"סריקת קוד מהמחשב\", ולכוון את המצלמה לכאן.").foregroundStyle(.secondary)
                if let img = qrImage(p.qrPayload) {
                    Image(nsImage: img).interpolation(.none).resizable().frame(width: 220, height: 220)
                        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
                Text("או להקליד את הקוד").foregroundStyle(.secondary)
                Text(p.display).font(.system(size: 34, weight: .bold, design: .monospaced)).environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int(p.expiresAt.timeIntervalSince(ctx.date)))
                    if left > 0 { Text("הקוד בתוקף עוד \(left / 60):\(String(format: "%02d", left % 60))").font(.callout).foregroundStyle(.secondary).monospacedDigit() }
                    else { Button("הקוד פג. ליצור קוד חדש") { Task { await start() } } }
                }
            } else {
                ProgressView()
            }
            Button(done ? "סגירה" : "ביטול") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(28).frame(width: 420)
        .task { await start() }
        .onDisappear {
            unwatch?()
            if let p = pairing { Task { try? await model.store.cancelPairing(p.code) } }   // a used or unused code is removed either way
        }
    }

    private func start() async {
        unwatch?()
        if let old = pairing { try? await model.store.cancelPairing(old.code) }
        guard let p = await model.createPairing(for: emp) else { dismiss(); return }
        pairing = p
        unwatch = model.store.watchPairing(p.code) { used in
            if used { done = true; Task { try? await Task.sleep(for: .seconds(1.6)); dismiss() } }
        }
        if let demo = model.store as? DemoStore {   // demo: pretend the phone scanned after a moment
            Task { try? await Task.sleep(for: .seconds(4)); demo.simulatePhoneUses(p.code) }
        }
    }

    private func qrImage(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size); img.addRepresentation(rep)
        return img
    }
}
