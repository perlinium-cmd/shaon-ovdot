import SwiftUI
import GoogleSignIn

@main
struct ShaonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("showMenuBar") private var showMenuBar = true
    @State private var auth = AuthService()
    @State private var model: AppModel?
    @State private var modelUid: String?
    private let demo = CommandLine.arguments.contains("-demo")

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if demo { DemoRoot() }
                else {
                    switch auth.state {
                    case .loading: ProgressView("טוען…")
                    case .signedOut: LoginView(auth: auth)
                    case .signedIn(let uid, _, _):
                        if let model, modelUid == uid { RootView().environment(model).environment(auth) }
                        else { ProgressView("טוען…").onAppear { start(uid) } }
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .frame(minWidth: 900, minHeight: 620)
            .tint(Color(red: 0.06, green: 0.46, blue: 0.43))
            .onOpenURL { url in
                if url.scheme == "shaon" {
                    // Widget tap: widgets always show the current month.
                    model?.month = currentMonth()
                    NotificationCenter.default.post(name: .openRoute, object: url)
                } else { _ = GIDSignIn.sharedInstance.handle(url) }
            }
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("עובדת חדשה") { NotificationCenter.default.post(name: .newEmployee, object: nil) }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .printItem) {
                Button("ייצוא לאקסל…") { NotificationCenter.default.post(name: .exportExcel, object: nil) }.keyboardShortcut("e")
                Button("שמירה כ-PDF…") { NotificationCenter.default.post(name: .exportPDF, object: nil) }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("הדפסה…") { NotificationCenter.default.post(name: .printReport, object: nil) }.keyboardShortcut("p")
            }
            CommandMenu("תצוגה") {
                Button("חודש קודם") { model?.month = shiftMonthBy(model?.month ?? currentMonth(), -1) }.keyboardShortcut("]")
                Button("חודש הבא") { model?.month = shiftMonthBy(model?.month ?? currentMonth(), 1) }.keyboardShortcut("[")
                Button("חודש נוכחי") { model?.month = currentMonth() }.keyboardShortcut("t")
                Divider()
                Button("סיכום חודשי") { NotificationCenter.default.post(name: .showSummary, object: nil) }.keyboardShortcut("2")
            }
        }
        WindowGroup("עובדת", id: "employee", for: String.self) { $id in
            if let model, let id {
                EmployeeView(empId: id).environment(model)
                    .toolbar { ToolbarItem(placement: .primaryAction) { MonthSwitcher().environment(model) } }
                    .environment(\.layoutDirection, .rightToLeft).frame(minWidth: 760, minHeight: 560)
                    .tint(Color(red: 0.06, green: 0.46, blue: 0.43))
            }
        }
        MenuBarExtra(isInserted: $showMenuBar) {
            if let model { MenuBarPanel().environment(model) }
            else { Text("התחבר/י באפליקציה כדי להתחיל").padding() }
        } label: { Image(systemName: "clock.badge.checkmark") }
        .menuBarExtraStyle(.window)
        Settings {
            if let model { SettingsView().environment(model).environment(auth) }
        }
    }

    private func start(_ uid: String) {
        let m = AppModel(store: FirestoreStore(uid: uid))
        model = m
        AppRuntime.model = m
        modelUid = uid
    }
}

/// `-demo` launch argument: in-memory sample data, no sign-in.
struct DemoRoot: View {
    @State private var model = AppModel(store: DemoStore())
    var body: some View { RootView().environment(model).onAppear { AppRuntime.model = model } }
}

struct LoginView: View {
    let auth: AuthService
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark").font(.system(size: 52)).foregroundStyle(.tint)
            Text("שעון עובדות").font(.largeTitle.weight(.bold))
            Text("רישום שעות ותשלום לעובדות, מכל מכשיר.").foregroundStyle(.secondary)
            Button { Task { await auth.signIn() } } label: { Label("התחברות עם Google", systemImage: "person.crop.circle") }
                .buttonStyle(.borderedProminent).controlSize(.large)
            if let e = auth.error { Text(e).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
        }.padding(40).frame(maxWidth: 420)
    }
}
