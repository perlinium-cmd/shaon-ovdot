import SwiftUI
import GoogleSignIn

@main
struct ShaonApp: App {
    @State private var auth = AuthService()
    @State private var model: AppModel?
    @State private var modelUid: String?
    private let demo = CommandLine.arguments.contains("-demo")

    var body: some Scene {
        WindowGroup {
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
            .onOpenURL { _ = GIDSignIn.sharedInstance.handle($0) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("עובדת חדשה") { NotificationCenter.default.post(name: .newEmployee, object: nil) }.keyboardShortcut("n")
            }
            CommandMenu("תצוגה") {
                Button("חודש קודם") { model?.month = shiftMonthBy(model?.month ?? currentMonth(), -1) }.keyboardShortcut("]")
                Button("חודש הבא") { model?.month = shiftMonthBy(model?.month ?? currentMonth(), 1) }.keyboardShortcut("[")
                Button("חודש נוכחי") { model?.month = currentMonth() }.keyboardShortcut("t")
                Divider()
                Button("סיכום חודשי") { NotificationCenter.default.post(name: .showSummary, object: nil) }.keyboardShortcut("2")
            }
        }
        Settings {
            if let model { SettingsView().environment(model).environment(auth) }
        }
    }

    private func start(_ uid: String) {
        let store = FirestoreStore(uid: uid)
        model = AppModel(store: store)
        modelUid = uid
    }
}

/// `-demo` launch argument: in-memory sample data, no sign-in.
struct DemoRoot: View {
    @State private var model = AppModel(store: DemoStore())
    var body: some View { RootView().environment(model) }
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
