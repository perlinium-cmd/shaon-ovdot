import SwiftUI
import Observation
import UserNotifications

@MainActor @Observable
final class AppModel {
    let store: DataStore
    var settings: AppSettings?
    var employees: [Employee]?
    var shifts: [Shift]?
    var month = currentMonth() { didSet { if month != oldValue { subscribeShifts() } } }
    var toast: String?
    var openShifts: [Shift] = []
    var devices: [Device] = []
    var requests: [ShiftRequest] = []
    var pendingRequests: [ShiftRequest] { requests.filter(\.isPending).sorted { ($0.createdAt ?? 0) < ($1.createdAt ?? 0) } }
    var notices: [Notice] = []   // newest first
    var unseenNotices: [Notice] { notices.filter { !$0.isSeen } }
    @ObservationIgnored private var seenOpen: Set<String>?
    @ObservationIgnored private var seenRequests: Set<String>?
    /// Notices already shown as a notification, kept across launches so ones that came in while the Mac was off still notify once.
    @ObservationIgnored private var notifiedNotices: Set<String> = []
    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored private var unsubs: [() -> Void] = []
    @ObservationIgnored private var unsubShifts: (() -> Void)?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var widgetSync: WidgetSync?

    init(store: DataStore) {
        self.store = store
        if !store.isDemo { notifiedNotices = Set(UserDefaults.standard.stringArray(forKey: "notifiedNotices") ?? []) }
        store.onProblem = { [weak self] msg in self?.say(msg, long: true) }
        unsubs.append(store.watchSettings { [weak self] in self?.settings = $0 })
        unsubs.append(store.watchEmployees { [weak self] in self?.employees = $0.sorted { $0.name.localizedCompare($1.name) == .orderedAscending } })
        subscribeShifts()
        unsubs.append(store.watchOpenShifts { [weak self] in self?.openShiftsChanged($0) })
        unsubs.append(store.watchDevices { [weak self] in self?.devices = $0.sorted { ($0.pairedAt ?? 0) < ($1.pairedAt ?? 0) } })
        unsubs.append(store.watchRequests { [weak self] in self?.requestsChanged($0) })
        unsubs.append(store.watchNotices { [weak self] in self?.noticesChanged($0) })
        if !store.isDemo {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            widgetSync = WidgetSync(store: store)
            observeQuickClock()
        }
    }
    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: phones: live status + notifications
    private func notify(_ title: String, _ body: String) {
        guard !store.isDemo else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    private func openShiftsChanged(_ list: [Shift]) {
        let ids = Set(list.map(\.id))
        if let seen = seenOpen {
            for s in list where !seen.contains(s.id) {
                notify("\(emp(s.empId)?.name ?? "עובדת") נכנסה לעבודה", "כניסה ב-\(fmt(s.in))")
            }
            for id in seen.subtracting(ids) {
                // Closed or undone. Tell only about a real clock-out (it shows up with an out time).
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, let s = self.shifts?.first(where: { $0.id == id }), !s.out.isEmpty else { return }
                    if self.notices.contains(where: { $0.shiftId == id && $0.closedShift }) { return }   // she typed the time: told by its notice
                    self.notify("\(self.emp(s.empId)?.name ?? "עובדת") יצאה מהעבודה", "\(self.fmt(s.in))–\(self.fmt(s.out)) · \(fmtHM(shiftMinutes(s.date, s.in, s.out))) שעות")
                }
            }
        }
        seenOpen = ids
        openShifts = list
    }
    private func requestsChanged(_ list: [ShiftRequest]) {
        let pending = Set(list.filter(\.isPending).map(\.id))
        if let seen = seenRequests {
            for r in list where r.isPending && !seen.contains(r.id) {
                notify("בקשה חדשה מ\(emp(r.empId)?.name ?? "עובדת")", r.type == "add" ? "הוספת משמרת ב-\(fmtDayMonth(r.date))" : "תיקון משמרת ב-\(fmtDayMonth(r.date))")
            }
        }
        seenRequests = pending
        requests = list
    }
    private func noticesChanged(_ list: [Notice]) {
        notices = list
        let fresh = list.filter { !$0.isSeen && !notifiedNotices.contains($0.id) }
        guard !fresh.isEmpty else { return }
        notifiedNotices.formUnion(fresh.map(\.id))
        if notifiedNotices.count > 400 { notifiedNotices.formIntersection(Set(list.map(\.id))) }   // forget old ones
        if !store.isDemo { UserDefaults.standard.set(Array(notifiedNotices), forKey: "notifiedNotices") }
        Task { @MainActor [weak self] in
            for _ in 0..<50 where self?.employees == nil { try? await Task.sleep(for: .milliseconds(200)) }   // for her name
            guard let self else { return }
            if fresh.count > 3 { self.notify("\(fresh.count) עדכוני שעות מהטלפון", "אפשר לראות אותם בעמוד הבקשות והעדכונים"); return }
            for n in fresh.reversed() { let d = self.describe(n); self.notify(d.title, d.detail) }
        }
    }
    /// Title and detail line for a change the phone saved without approval.
    func describe(_ n: Notice) -> (title: String, detail: String) {
        let name = emp(n.empId)?.name ?? "עובדת"
        let day = "\(fmtWeekday(n.date)) \(fmtDayMonth(n.date))"
        let hours = { (a: String, b: String) in fmtHM(shiftMinutes(n.date, a, b)) }
        let span = n.out.isEmpty ? "כניסה ב-\(fmt(n.in)), עדיין במשמרת" : "\(fmt(n.in))–\(fmt(n.out)) · \(hours(n.in, n.out)) שעות"
        let movedIn = n.movedIn ? "כניסה \(fmt(n.in)) במקום \(fmt(n.prevIn ?? ""))" : nil
        let movedOut = n.movedOut ? "יציאה \(fmt(n.out)) במקום \(fmt(n.prevOut ?? ""))" : nil
        let second = n.edit == 2 ? "שינוי שני במשמרת הזו" : nil
        let line = { (parts: [String?]) in parts.compactMap { $0 }.joined(separator: " · ") }
        if n.type == "manual" { return ("\(name) הזינה שעות", line([day, span])) }
        if n.closedShift { return ("\(name) רשמה שעת יציאה", line([day, span, movedIn, second])) }
        if n.out.isEmpty { return ("\(name) שינתה שעת כניסה", line([day, movedIn, "עדיין במשמרת", second])) }
        // A finished shift: what changed, and the total before and after (that's what changes the pay).
        var total: String?
        if let pi = n.prevIn, let po = n.prevOut, !po.isEmpty { total = "סה״כ \(hours(n.in, n.out)) שעות במקום \(hours(pi, po))" }
        return ("\(name) שינתה שעות", line([day, movedIn, movedOut, total, second]))
    }
    func markNoticesSeen() async {
        let ids = unseenNotices.map(\.id)
        guard !ids.isEmpty else { return }
        do { try await store.markNoticesSeen(ids) } catch { print(error) }
    }
    func openShift(of empId: String) -> Shift? { openShifts.filter { $0.empId == empId }.max { ($0.inAt ?? 0) < ($1.inAt ?? 0) } }
    func devices(of empId: String) -> [Device] { devices.filter { $0.empId == empId } }

    func createPairing(for e: Employee) async -> Pairing? {
        do { return try await store.createPairing(empId: e.id, empName: e.name) } catch { fail(error); return nil }
    }
    func disconnect(_ d: Device) async {
        do { try await store.disconnect(d); say("הטלפון נותק") } catch { fail(error) }
    }
    func decide(_ r: ShiftRequest, approve: Bool) async {
        do {
            try await store.decide(r, approve: approve, rate: rate(for: emp(r.empId)))
            say(approve ? "הבקשה אושרה והמשמרת עודכנה" : "הבקשה נדחתה")
        } catch let e as StoreError { say(e.errorDescription ?? "") } catch { fail(error) }
    }
    /// The shift a request is about (from this month's list, or the live list).
    func shift(_ id: String?) -> Shift? {
        guard let id else { return nil }
        return shifts?.first { $0.id == id } ?? openShifts.first { $0.id == id }
    }
    private func subscribeShifts() {
        unsubShifts?(); shifts = nil
        unsubShifts = store.watchShifts(month: month) { [weak self] in self?.shifts = $0 }
    }

    var isLoaded: Bool { settings != nil && employees != nil && shifts != nil }
    var defaultRate: Double? { settings?.defaultRate }
    var twelve: Bool { settings?.is12 ?? false }
    func emp(_ id: String) -> Employee? { employees?.first { $0.id == id } }
    func fmt(_ t: String) -> String { fmtTime(t, twelve: twelve) }
    func pay(_ s: Shift) -> Double { shiftPay(s, emp(s.empId), defaultRate: defaultRate) }
    func rate(for e: Employee?) -> Double { effRate(e, defaultRate: defaultRate) }
    var agg: [String: Agg] { aggregate(shifts ?? [], employees: employees ?? [], defaultRate: defaultRate) }
    func shifts(of empId: String) -> [Shift] {
        (shifts ?? []).filter { $0.empId == empId }.sorted { ($0.date, $0.in) > ($1.date, $1.in) }
    }
    /// Employees to show: active ones, plus archived ones that have shifts this month.
    func visibleEmployees() -> [Employee] {
        let a = agg
        return (employees ?? []).filter { $0.isActive || a[$0.id] != nil }
    }

    // MARK: feedback + undo
    func say(_ msg: String, long: Bool = false) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(for: .seconds(long ? 6 : 2.2)); if !Task.isCancelled { toast = nil } }
    }
    func fail(_ e: Error) {
        if let e = e as? StoreError { say(e.errorDescription ?? "", long: true) } else { say("משהו השתבש, נסה שוב") }
        print(e)
    }

    /// Runs `action`, and registers ⌘Z / ⇧⌘Z for it.
    private func undoable(_ name: String, undo: @escaping @MainActor () async throws -> Void, redo: @escaping @MainActor () async throws -> Void) {
        undoManager?.registerUndo(withTarget: self) { m in
            Task { @MainActor in
                do { try await undo() } catch { m.fail(error) }
                m.undoable(name, undo: redo, redo: undo)
            }
        }
        undoManager?.setActionName(name)
    }

    // MARK: shifts
    @discardableResult
    func addShift(_ s: Shift) async -> Bool {
        do { try await addShiftOrThrow(s); return true } catch { fail(error); return false }
    }
    private func addShiftOrThrow(_ s: Shift) async throws {
        var s = s; s.createdAt = Date().timeIntervalSince1970 * 1000
        let id = try await store.addShift(s); s.id = id
        undoable("הוספת משמרת", undo: { try await self.store.commit([.delete("shifts", id)]) },
                 redo: { _ = try await self.store.addShift(s) })
        say("נשמר: \(fmtDayMonth(s.date)) · \(fmtHM(shiftMinutes(s.date, s.in, s.out))) שעות")
    }

    /// Runs writes that belong together as one, and registers ⌘Z / ⇧⌘Z that put back exactly the documents in `refs`
    /// and remove the new ones in `created` (known not to exist yet, so nothing has to be read for them — that works
    /// without internet too).
    private func commitUndoable(_ name: String, refs: [(col: String, id: String)], created: [(col: String, id: String)] = [],
                                _ writes: [DocWrite]) async throws {
        let before = try await store.snapshot(refs) + created.map { DocSnapshot(col: $0.col, id: $0.id, data: nil) }
        try await store.commit(writes)
        // The writes are done; if this copy can't be read back, there is just no ⇧⌘Z (never an error for a saved change).
        let after = (try? await store.snapshot(refs + created)) ?? []
        undoable(name, undo: { try await self.store.restore(before) }, redo: { try await self.store.restore(after) })
    }

    // MARK: quick clock (widget)
    @ObservationIgnored private var savingClock = false

    private func observeQuickClock() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let model = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in await model.saveClockedShifts() }
        }, QuickClock.changedNotification as CFString, nil, .deliverImmediately)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.saveClockedShifts() }
        }
        Task { await saveClockedShifts() }
    }

    /// Saves shifts clocked from the widget. Each one leaves the queue only after it's stored, under an id made from
    /// its queue entry — so if the app stops between the two steps, the next run finds it saved and never adds it twice.
    func saveClockedShifts() async {
        guard !savingClock else { return }
        savingClock = true; defer { savingClock = false }
        for _ in 0..<100 where employees == nil || settings == nil { try? await Task.sleep(for: .milliseconds(200)) }
        guard let employees else { return }
        for p in QuickClock.load().pending {
            guard let e = employees.first(where: { $0.id == p.empId }) else { QuickClock.removePending(p.id); continue }
            let id = "qc-" + p.id.uuidString
            do {
                // Already saved by an earlier run? (Our own writes are always in this Mac's copy, so "not found" means not saved.)
                if (try? await store.snapshot([("shifts", id)]))?.first?.data == nil {
                    try await addShiftOrThrow(Shift(id: id, empId: e.id, date: p.date, month: String(p.date.prefix(7)), in: p.in, out: p.out,
                                                    rate: rate(for: e), special: nil, paid: false))
                    if let m = p.minutes, m >= 24 * 60 {
                        say("השעון בווידג׳ט רץ ל\(e.name) יותר מיממה (\(fmtHM(m)) שעות). נשמרה משמרת \(p.in)–\(p.out) – כדאי לבדוק ולתקן.", long: true)
                    }
                }
                QuickClock.removePending(p.id)
            } catch { fail(error) }
        }
    }

    // MARK: editing and deleting shifts
    /// Changes the times, date or special rate of a shift (only those fields, so nothing someone else changed
    /// meanwhile — like a payment — is overwritten). A paid shift keeps what was paid for it: its hours, date and
    /// rate can change only after its "paid" mark is removed. Returns false when nothing was saved.
    @discardableResult
    func updateShift(_ new: Shift) async -> Bool {
        guard let old = shifts?.first(where: { $0.id == new.id }) else { return false }
        if old.isPaid && (old.date != new.date || old.in != new.in || old.out != new.out || !sameSpecial(old.special, new.special)) {
            say("המשמרת כבר סומנה כשולמה, ולכן אי אפשר לשנות בה שעות, תאריך או תעריף. קודם מבטלים את הסימון \"שולם\", ואז מעדכנים.", long: true)
            return false
        }
        var fields: [String: Any] = ["date": new.date, "month": new.month, "in": new.in, "out": new.out,
                                     "special": new.special.map { ["rate": $0.rate ?? NSNull(), "hours": $0.hours ?? NSNull()] as [String: Any] } ?? NSNull()]
        if old.isOpen && !new.isOpen { fields["open"] = false }   // the manager closed a running phone shift
        do {
            try await commitUndoable("עדכון משמרת", refs: [("shifts", new.id)], [.update("shifts", new.id, fields)])
            say("המשמרת עודכנה")
            return true
        } catch { fail(error); return false }
    }

    /// Deletes shifts. Paid ones also leave their payment records — in the same write.
    func deleteShifts(_ ids: [String]) async {
        let old = (shifts ?? []).filter { ids.contains($0.id) }
        guard !old.isEmpty else { return }
        do {
            let (paymentWrites, paymentRefs) = try await paymentChanges(removing: old.filter(\.isPaid))
            try await commitUndoable("מחיקת משמרות", refs: old.map { ("shifts", $0.id) } + paymentRefs,
                                     paymentWrites + old.map { .delete("shifts", $0.id) })
            say(old.count == 1 ? "המשמרת נמחקה" : "\(old.count) משמרות נמחקו")
        } catch { fail(error) }
    }

    // MARK: payments (the same records as the website: users/{uid}/payments)
    /// Last way of paying chosen on this Mac (the website keeps its own).
    var payMethod: String {
        get { UserDefaults.standard.string(forKey: "payMethod") ?? "מזומן" }
        set { UserDefaults.standard.set(newValue, forKey: "payMethod") }
    }
    @ObservationIgnored private var payBusy = Set<String>()

    /// Marks shifts as paid and records the payment — one record per employee, with the exact sum of its shifts —
    /// all in one write. Only shifts that are, right now, finished and unpaid are included, so a second click or
    /// another device that paid them meanwhile can never pay twice.
    func markPaid(_ ids: [String], method: String? = nil, date: String = todayStr()) async {
        let running = Set(openShifts.map(\.id))
        let all = (shifts ?? []).filter { ids.contains($0.id) && !payBusy.contains($0.id) }
        let todo = all.filter { !$0.isPaid && !$0.isOpen && !running.contains($0.id) }
        if todo.isEmpty {
            if all.contains(where: { $0.isOpen || running.contains($0.id) }) { say("משמרת פעילה אי אפשר לסמן כשולמה") }
            return
        }
        let method = method ?? payMethod
        let now = Date().timeIntervalSince1970 * 1000
        var writes: [DocWrite] = [], created: [(col: String, id: String)] = [], total = 0
        for (empId, list) in Dictionary(grouping: todo, by: \.empId).sorted(by: { $0.key < $1.key }) {
            let amount = list.reduce(0) { $0 + shiftPayAgorot($1, emp(empId), defaultRate: defaultRate) }
            total += amount
            let pid = store.newId("payments")
            created.append(("payments", pid))
            writes.append(.set("payments", pid, ["empId": empId, "date": date, "amount": Double(amount) / 100, "method": method,
                                                 "shiftIds": list.map(\.id), "createdAt": now]))
            writes += list.map { .update("shifts", $0.id, ["paid": true, "paidAt": now, "paymentId": pid]) }
        }
        payBusy.formUnion(todo.map(\.id)); defer { payBusy.subtract(todo.map(\.id)) }
        do {
            try await commitUndoable("סימון כשולם", refs: todo.map { ("shifts", $0.id) }, created: created, writes)
            payMethod = method
            say("סומן כשולם · \(fmtMoney(Double(total) / 100)) · \(method)")
        } catch { fail(error) }
    }

    /// Removes the "paid" mark and takes the shifts out of their payment records (a record left with no shift is
    /// deleted) — in one write.
    func markUnpaid(_ ids: [String]) async {
        let todo = (shifts ?? []).filter { ids.contains($0.id) && $0.isPaid && !payBusy.contains($0.id) }
        guard !todo.isEmpty else { return }
        payBusy.formUnion(todo.map(\.id)); defer { payBusy.subtract(todo.map(\.id)) }
        do {
            let (paymentWrites, paymentRefs) = try await paymentChanges(removing: todo)
            try await commitUndoable("ביטול סימון שולם", refs: todo.map { ("shifts", $0.id) } + paymentRefs,
                                     todo.map { .update("shifts", $0.id, ["paid": false, "paidAt": NSNull(), "paymentId": NSNull()]) } + paymentWrites)
        } catch { fail(error) }
    }

    /// The writes that take paid shifts out of their payment records: the shift leaves `shiftIds` and its pay leaves
    /// `amount` (exact, in agorot); a record left with no shift is deleted.
    private func paymentChanges(removing paid: [Shift]) async throws -> ([DocWrite], [(col: String, id: String)]) {
        let byPayment = Dictionary(grouping: paid.filter { $0.paymentId != nil }, by: { $0.paymentId! })
        guard !byPayment.isEmpty else { return ([], []) }
        let refs = byPayment.keys.sorted().map { (col: "payments", id: $0) }
        var writes: [DocWrite] = []
        for p in try await store.snapshot(refs) {
            guard let data = p.data, let removed = byPayment[p.id] else { continue }
            let gone = Set(removed.map(\.id))
            let left = (data["shiftIds"] as? [String] ?? []).filter { !gone.contains($0) }
            if left.isEmpty { writes.append(.delete("payments", p.id)); continue }
            let was = toAgorot((data["amount"] as? NSNumber)?.doubleValue ?? 0) ?? 0
            let minus = removed.reduce(0) { $0 + shiftPayAgorot($1, emp($1.empId), defaultRate: defaultRate) }
            writes.append(.update("payments", p.id, ["shiftIds": left, "amount": Double(max(0, was - minus)) / 100]))
        }
        return (writes, refs)
    }

    // MARK: employees + settings
    func addEmployee(name: String, rate: Double?) async -> String? {
        do { let id = try await store.addEmployee(Employee(name: name, rate: rate, active: true, createdAt: Date().timeIntervalSince1970 * 1000)); say("\(name) נוספה"); return id }
        catch { fail(error); return nil }
    }
    /// Saves an employee. If her rate changes, her past shifts that have no rate of their own (from her phone) first get
    /// the old rate, so past work keeps the rate it was done at. That needs the server: offline nothing is saved.
    @discardableResult
    func updateEmployee(_ e: Employee) async -> Bool {
        do {
            if let old = emp(e.id), rate(for: old) != rate(for: e) { try await lockRates(of: [old.id], at: { _ in self.rate(for: old) }) }
            try await store.updateEmployee(e)
            return true
        } catch { fail(error); return false }
    }
    /// Before a rate changes, write the current rate onto shifts that have none (phone shifts),
    /// so past work keeps the rate it was done at, like shifts entered by hand.
    private func lockRates(of empIds: [String], at rateFor: (String) -> Double) async throws {
        var rates: [String: Double] = [:]
        for id in empIds {
            for s in try await store.shiftsWithoutRate(empId: id) { rates[s.id] = rateFor(id) }
        }
        if !rates.isEmpty { try await store.setRates(rates) }
    }
    @discardableResult
    func deleteEmployee(_ e: Employee) async -> Bool {
        do { try await store.deleteEmployee(e.id); say("\(e.name) נמחקה"); return true } catch { fail(error); return false }
    }
    @discardableResult
    func saveSettings(_ change: (inout AppSettings) -> Void) async -> Bool {
        var s = settings ?? AppSettings()
        change(&s)
        do {
            if let oldRate = settings?.defaultRate, s.defaultRate != oldRate {
                let usingDefault = (employees ?? []).filter { $0.rate == nil }.map(\.id)
                try await lockRates(of: usingDefault, at: { _ in oldRate })
            }
            settings = s
            try await store.saveSettings(s)
            return true
        } catch { fail(error); return false }
    }
}

/// Same special rate? (none, and one without a rate, are the same: both pay nothing extra).
func sameSpecial(_ a: Special?, _ b: Special?) -> Bool {
    let x = a?.rate == nil ? nil : a, y = b?.rate == nil ? nil : b
    return x?.rate == y?.rate && x?.hours == y?.hours
}
