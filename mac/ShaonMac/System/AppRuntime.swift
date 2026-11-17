import SwiftUI
import UserNotifications
import ServiceManagement

/// Process-wide access to the live model, for App Intents, the Dock menu and notifications.
@MainActor
enum AppRuntime {
    static var model: AppModel?

    /// Waits (up to `seconds`) for sign-in + first data load — intents can launch the app cold.
    static func ready(seconds: Double = 10) async -> AppModel? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let m = model, m.isLoaded { return m }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One copy only: a second one would fight the first over Firestore's local database. (Tests and -demo don't open it.)
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil, !CommandLine.arguments.contains("-demo"),
              let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0 != .current }
        if let first = others.first { first.activate(); NSApp.terminate(nil) }
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let a = NSMenuItem(title: "עובדת חדשה", action: #selector(newEmployee), keyEquivalent: ""); a.target = self
        let b = NSMenuItem(title: "סיכום חודשי", action: #selector(summary), keyEquivalent: ""); b.target = self
        menu.addItem(a); menu.addItem(b)
        return menu
    }
    @objc private func newEmployee() { NSApp.activate(ignoringOtherApps: true); NotificationCenter.default.post(name: .newEmployee, object: nil) }
    @objc private func summary() { NSApp.activate(ignoringOtherApps: true); NotificationCenter.default.post(name: .showSummary, object: nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Dock badge + a local reminder near the end of the month when there is still money to pay.
/// (The desktop widgets get their data from WidgetSync.)
@MainActor
enum Reminders {
    static func update(model: AppModel) {
        let agg = model.agg
        let owing = agg.values.filter { $0.unpaid > 0 && !$0.shifts.isEmpty }
        NSApp.dockTile.badgeLabel = owing.isEmpty ? nil : String(owing.count)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["month-end"])
        guard UserDefaults.standard.bool(forKey: "monthEndReminder"), model.month == currentMonth(), !owing.isEmpty else { return }
        let total = Double(owing.reduce(0) { $0 + $1.payAgorot - $1.paidAgorot }) / 100
        let range = gregorian.range(of: .day, in: .month, for: .now)!
        var c = gregorian.dateComponents([.year, .month], from: .now)
        c.day = range.upperBound - 1; c.hour = 10
        guard let fire = gregorian.date(from: c), fire > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "שעון עובדות"
        content.body = "החודש נגמר בקרוב, נותרו \(fmtMoney(total)) לתשלום ל-\(owing.count) עובדות."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: gregorian.dateComponents([.year, .month, .day, .hour], from: fire), repeats: false)
        center.add(UNNotificationRequest(identifier: "month-end", content: content, trigger: trigger))
    }
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

enum LaunchAtLogin {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) { try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()) }
}
