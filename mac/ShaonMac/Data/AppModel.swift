import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    let store: DataStore
    var settings: AppSettings?
    var employees: [Employee]?
    var shifts: [Shift]?
    var month = currentMonth() { didSet { if month != oldValue { subscribeShifts() } } }
    var toast: String?
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
        if !store.isDemo {
            widgetSync = WidgetSync(store: store)
            observeQuickClock()
        }
    }
    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
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
        guard !ids.isEmpty else { return }
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
    func updateEmployee(_ e: Employee) async { do { try await store.updateEmployee(e) } catch { fail(error) } }
    func deleteEmployee(_ e: Employee) async { do { try await store.deleteEmployee(e.id); say("\(e.name) נמחקה") } catch { fail(error) } }
    func saveSettings(_ change: (inout AppSettings) -> Void) async {
        var s = settings ?? AppSettings()
        change(&s)
        settings = s
        do { try await store.saveSettings(s) } catch { fail(error) }
    }
}
