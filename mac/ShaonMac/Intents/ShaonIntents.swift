import AppIntents
import SwiftUI

struct EmployeeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "עובדת"
    static let defaultQuery = EmployeeQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct EmployeeQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [EmployeeEntity] {
        guard let m = await AppRuntime.ready() else { return [] }
        return (m.employees ?? []).filter { identifiers.contains($0.id) }.map { EmployeeEntity(id: $0.id, name: $0.name) }
    }
    @MainActor func suggestedEntities() async throws -> [EmployeeEntity] {
        guard let m = await AppRuntime.ready() else { return [] }
        return (m.employees ?? []).filter(\.isActive).map { EmployeeEntity(id: $0.id, name: $0.name) }
    }
}

struct UnpaidBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "כמה נותר לתשלום"
    static let description = IntentDescription("כמה כסף נותר לשלם לעובדות החודש הנוכחי.")
    static let openAppWhenRun = false

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let m = await AppRuntime.ready() else { throw IntentError.notReady }
        let unpaid = m.agg.values.reduce(0) { $0 + $1.unpaid }
        let text = unpaid <= 0 ? "הכל שולם ל\(fmtMonthName(m.month))" : "נותרו \(fmtMoney(unpaid)) לתשלום ב\(fmtMonthName(m.month))"
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct AddShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "הוספת משמרת"
    static let description = IntentDescription("רושם משמרת לעובדת.")
    @Parameter(title: "עובדת") var employee: EmployeeEntity
    @Parameter(title: "כניסה") var start: Date
    @Parameter(title: "יציאה") var end: Date
    @Parameter(title: "תאריך") var day: Date?
    static var parameterSummary: some ParameterSummary { Summary("הוסף משמרת ל\(\.$employee) מ-\(\.$start) עד \(\.$end)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let m = await AppRuntime.ready(), let e = m.emp(employee.id) else { throw IntentError.notReady }
        func hm(_ d: Date) -> String { let c = gregorian.dateComponents([.hour, .minute], from: d); return String(format: "%02d:%02d", c.hour!, c.minute!) }
        let tin = hm(start), tout = hm(end)
        guard tin != tout else { throw IntentError.badTimes }
        let date = dateStr(day ?? .now)
        guard await m.addShift(Shift(empId: e.id, date: date, month: String(date.prefix(7)), in: tin, out: tout, rate: m.rate(for: e), special: nil, paid: false))
        else { throw IntentError.notSaved }
        return .result(dialog: "נשמר: \(e.name), \(fmtHM(shiftMinutes(date, tin, tout))) שעות")
    }
}

struct OpenEmployeeIntent: AppIntent {
    static let title: LocalizedStringResource = "פתיחת עובדת"
    static let openAppWhenRun = true
    @Parameter(title: "עובדת") var employee: EmployeeEntity
    @MainActor func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .openEmployee, object: employee.id)
        return .result()
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady, badTimes, notSaved
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: "האפליקציה לא מוכנה. התחבר/י אליה ונסה/י שוב."
        case .badTimes: "שעת היציאה זהה לשעת הכניסה."
        case .notSaved: "המשמרת לא נשמרה. פתח/י את האפליקציה כדי לראות למה."
        }
    }
}

struct ShaonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: UnpaidBalanceIntent(), phrases: ["כמה נותר לתשלום ב\(.applicationName)", "מה היתרה ב\(.applicationName)"],
                    shortTitle: "יתרה לתשלום", systemImageName: "shekelsign.circle")
        AppShortcut(intent: AddShiftIntent(), phrases: ["הוסף משמרת ב\(.applicationName)"], shortTitle: "הוספת משמרת", systemImageName: "plus.circle")
        AppShortcut(intent: OpenEmployeeIntent(), phrases: ["פתח עובדת ב\(.applicationName)"], shortTitle: "פתיחת עובדת", systemImageName: "person")
    }
}

extension Notification.Name { static let openEmployee = Notification.Name("shaon.openEmployee") }
