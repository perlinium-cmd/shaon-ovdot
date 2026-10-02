import Foundation
import WidgetKit

/// Keeps the widgets' snapshot fresh. Listens to the *current* month (and the previous one, for the weekly chart)
/// independently of whichever month the window is showing.
@MainActor
final class WidgetSync {
    private let store: DataStore
    private var settings: AppSettings?
    private var employees: [Employee]?
    private var cur: [Shift]?
    private var prev: [Shift]?
    private var month = ""
    private var unsubs: [() -> Void] = []
    private var unsubShifts: [() -> Void] = []
    private var pending: Task<Void, Never>?
    private var timer: Timer?

    init(store: DataStore) {
        self.store = store
        unsubs.append(store.watchSettings { [weak self] in self?.settings = $0; self?.schedule() })
        unsubs.append(store.watchEmployees { [weak self] in self?.employees = $0; self?.schedule() })
        followCurrentMonth()
        // The month can roll over while the app stays open.
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.followCurrentMonth() }
        }
    }

    private func followCurrentMonth() {
        let m = currentMonth()
        guard m != month else { return }
        month = m
        unsubShifts.forEach { $0() }
        cur = nil; prev = nil
        unsubShifts = [
            store.watchShifts(month: m) { [weak self] in self?.cur = $0; self?.schedule() },
            store.watchShifts(month: shiftMonthBy(m, -1)) { [weak self] in self?.prev = $0; self?.schedule() },
        ]
    }

    /// Coalesces bursts of listener callbacks into one write.
    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, let settings, let employees, let cur, let prev else { return }
            let snap = makeWidgetSnapshot(month: month, settings: settings, employees: employees, current: cur, previous: prev)
            if WidgetStore.save(snap) { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    static func clear() {
        if WidgetStore.save(nil) { WidgetCenter.shared.reloadAllTimelines() }
    }
}

func makeWidgetSnapshot(month: String, settings: AppSettings, employees: [Employee], current: [Shift], previous: [Shift]) -> WidgetSnapshot {
    let agg = aggregate(current, employees: employees, defaultRate: settings.defaultRate)
    let recent = current + previous
    let emps = employees
        .filter { $0.isActive || agg[$0.id] != nil }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        .map { e -> WidgetSnapshot.Emp in
            let a = agg[e.id] ?? Agg()
            let last = recent.filter { $0.empId == e.id }.max { ($0.date, $0.in) < ($1.date, $1.in) }
            return .init(id: e.id, name: e.name, active: e.isActive, minutes: a.minutes, pay: round2(a.pay), paidPay: round2(a.paidPay),
                         shifts: a.shifts.count, paidShifts: a.paidCount,
                         last: last.map { .init(date: $0.date, in: $0.in, out: $0.out) })
        }
    var days: [String: [String: Int]] = [:]
    for s in recent { days[s.date, default: [:]][s.empId, default: 0] += shiftMinutes(s.in, s.out) }
    return WidgetSnapshot(month: month, twelve: settings.is12, employees: emps, days: days, updatedAt: .now)
}
