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
    @ObservationIgnored private var seenOpen: Set<String>?
    @ObservationIgnored private var seenRequests: Set<String>?
    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored private var unsubs: [() -> Void] = []
    @ObservationIgnored private var unsubShifts: (() -> Void)?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var widgetSync: WidgetSync?

    init(store: DataStore) {
        self.store = store
        unsubs.append(store.watchSettings { [weak self] in self?.settings = $0 })
        unsubs.append(store.watchEmployees { [weak self] in self?.employees = $0.sorted { $0.name.localizedCompare($1.name) == .orderedAscending } })
        subscribeShifts()
        unsubs.append(store.watchOpenShifts { [weak self] in self?.openShiftsChanged($0) })
        unsubs.append(store.watchDevices { [weak self] in self?.devices = $0.sorted { ($0.pairedAt ?? 0) < ($1.pairedAt ?? 0) } })
        unsubs.append(store.watchRequests { [weak self] in self?.requestsChanged($0) })
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
                    self.notify("\(self.emp(s.empId)?.name ?? "עובדת") יצאה מהעבודה", "\(self.fmt(s.in))–\(self.fmt(s.out)) · \(fmtHM(shiftMinutes(s.in, s.out))) שעות")
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
    func say(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(for: .seconds(2.2)); if !Task.isCancelled { toast = nil } }
    }
    func fail(_ e: Error) { say("משהו השתבש, נסה שוב"); print(e) }

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
    func addShift(_ s: Shift) async {
        do { try await addShiftOrThrow(s) } catch { fail(error) }
    }
    private func addShiftOrThrow(_ s: Shift) async throws {
        var s = s; s.createdAt = Date().timeIntervalSince1970 * 1000
        let id = try await store.addShift(s); s.id = id
        let saved = s
        undoable("הוספת משמרת", undo: { try await self.store.deleteShifts([id]) }, redo: { try await self.store.restoreShifts([saved]) })
        say("נשמר: \(fmtDayMonth(s.date)) · \(fmtHM(shiftMinutes(s.in, s.out))) שעות")
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

    /// Saves shifts clocked from the widget. Each one leaves the queue only after it's stored.
    func saveClockedShifts() async {
        guard !savingClock else { return }
        savingClock = true; defer { savingClock = false }
        for _ in 0..<100 where employees == nil || settings == nil { try? await Task.sleep(for: .milliseconds(200)) }
        guard let employees else { return }
        for p in QuickClock.load().pending {
            guard let e = employees.first(where: { $0.id == p.empId }) else { QuickClock.removePending(p.id); continue }
            do {
                try await addShiftOrThrow(Shift(empId: e.id, date: p.date, month: String(p.date.prefix(7)), in: p.in, out: p.out,
                                                rate: rate(for: e), special: nil, paid: false))
                QuickClock.removePending(p.id)
            } catch { fail(error) }
        }
    }
    func updateShift(_ new: Shift) async {
        guard let old = shifts?.first(where: { $0.id == new.id }) else { return }
        do {
            try await store.updateShift(new)
            undoable("עדכון משמרת", undo: { try await self.store.updateShift(old) }, redo: { try await self.store.updateShift(new) })
            say("המשמרת עודכנה")
        } catch { fail(error) }
    }
    func deleteShifts(_ ids: [String]) async {
        let old = (shifts ?? []).filter { ids.contains($0.id) }
        guard !old.isEmpty else { return }
        do {
            try await store.deleteShifts(old.map(\.id))
            undoable("מחיקת משמרות", undo: { try await self.store.restoreShifts(old) }, redo: { try await self.store.deleteShifts(old.map(\.id)) })
            say(old.count == 1 ? "המשמרת נמחקה" : "\(old.count) משמרות נמחקו")
        } catch { fail(error) }
    }
    func setPaid(_ ids: [String], paid: Bool) async {
        // A running shift has no pay yet, and marking it paid would stop the phone from clocking out.
        let running = Set((shifts ?? []).filter(\.isOpen).map(\.id)).union(openShifts.map(\.id))
        let ids = paid ? ids.filter { !running.contains($0) } : ids
        if ids.isEmpty { if paid { say("משמרת פעילה אי אפשר לסמן כשולמה") }; return }
        do {
            try await store.setPaid(ids, paid: paid)
            undoable(paid ? "סימון כשולם" : "ביטול סימון שולם", undo: { try await self.store.setPaid(ids, paid: !paid) }, redo: { try await self.store.setPaid(ids, paid: paid) })
        } catch { fail(error) }
    }

    // MARK: employees + settings
    func addEmployee(name: String, rate: Double?) async -> String? {
        do { let id = try await store.addEmployee(Employee(name: name, rate: rate, active: true, createdAt: Date().timeIntervalSince1970 * 1000)); say("\(name) נוספה"); return id }
        catch { fail(error); return nil }
    }
    func updateEmployee(_ e: Employee) async {
        do {
            if let old = emp(e.id), rate(for: old) != rate(for: e) { try await lockRates(of: [old.id], at: { _ in self.rate(for: old) }) }
            try await store.updateEmployee(e)
        } catch { fail(error) }
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
    func deleteEmployee(_ e: Employee) async { do { try await store.deleteEmployee(e.id); say("\(e.name) נמחקה") } catch { fail(error) } }
    func saveSettings(_ change: (inout AppSettings) -> Void) async {
        var s = settings ?? AppSettings()
        change(&s)
        do {
            if let oldRate = settings?.defaultRate, s.defaultRate != oldRate {
                let usingDefault = (employees ?? []).filter { $0.rate == nil }.map(\.id)
                try await lockRates(of: usingDefault, at: { _ in oldRate })
            }
            settings = s
            try await store.saveSettings(s)
        } catch { fail(error) }
    }
}
