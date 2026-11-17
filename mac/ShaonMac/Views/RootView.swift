import SwiftUI

enum Route: Hashable {
    case summary, requests, phones, employee(String)
    init?(launchArg a: String?) {
        switch a {
        case "requests": self = .requests
        case "phones": self = .phones
        case let a? where a.hasPrefix("emp:"): self = .employee(String(a.dropFirst(4)))
        default: return nil
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    // `-route requests|phones|emp:<id>` opens a page directly (used for screenshots of the demo).
    @State private var route: Route? = Route(launchArg: UserDefaults.standard.string(forKey: "route")) ?? .summary
    @State private var newEmployee = false
    @State private var search = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.denied { DeniedView() }
            else if !model.isLoaded { ProgressView("טוען…") }
            else if model.defaultRate == nil { Onboarding(step: 1) }
            else if model.visibleEmployees().isEmpty && (model.employees ?? []).isEmpty { Onboarding(step: 2) }
            else { main }
        }
        .onAppear { model.undoManager = undoManager; Reminders.update(model: model) }
        .onChange(of: model.agg.values.map(\.unpaid)) { _, _ in Reminders.update(model: model) }
        .onChange(of: model.employees) { _, list in
            if case .employee(let id) = route, let list, !list.contains(where: { $0.id == id }) { route = .summary }
        }
        .onChange(of: undoManager) { _, u in model.undoManager = u }
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t).padding(.horizontal, 14).padding(.vertical, 8).background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.toast)
    }

    private var main: some View {
        NavigationSplitView {
            let agg = model.agg
            List(selection: $route) {
                Label("סיכום חודשי", systemImage: "chart.bar").tag(Route.summary)
                Label("בקשות ועדכונים", systemImage: "tray")
                    .badge(model.pendingRequests.count + model.unseenNotices.count)
                    .tag(Route.requests)
                Label("טלפונים מחוברים", systemImage: "iphone.gen3").tag(Route.phones)
                let lay = model.sidebarLayout()
                let byId = Dictionary(uniqueKeysWithValues: model.visibleEmployees().map { ($0.id, $0) })
                let canMove = search.isEmpty
                let pinnedRows = shown(lay.pinned, byId)
                if !pinnedRows.isEmpty {
                    Section("נעוצות") {
                        ForEach(pinnedRows) { e in row(e, agg[e.id]).tag(Route.employee(e.id)).contextMenu { menu(e, lay) } }
                            .onMove(perform: canMove ? { model.applyLayout(lay.moved(pinnedGroup: true, from: $0, to: $1)) } : nil)
                    }
                }
                Section("עובדות") {
                    ForEach(shown(lay.rest, byId)) { e in row(e, agg[e.id]).tag(Route.employee(e.id)).contextMenu { menu(e, lay) } }
                        .onMove(perform: canMove ? { model.applyLayout(lay.moved(pinnedGroup: false, from: $0, to: $1)) } : nil)
                }
                let arch = filtered(active: false)
                if !arch.isEmpty {
                    Section("ארכיון") { ForEach(arch) { e in row(e, agg[e.id]).tag(Route.employee(e.id)).foregroundStyle(.secondary) } }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "חיפוש עובדת")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar { ToolbarItem { Button { newEmployee = true } label: { Label("עובדת חדשה", systemImage: "person.badge.plus") }.help("עובדת חדשה (⌘N)") } }
        } detail: {
            VStack(spacing: 0) {
                LiveBanner { route = .employee($0) }
                Group {
                    switch route ?? .summary {
                    case .summary: SummaryView { route = .employee($0) }
                    case .requests: RequestsView { route = .employee($0) }
                    case .phones: PhonesView()
                    case .employee(let id): EmployeeView(empId: id).id(id)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .toolbar { ToolbarItem(placement: .navigation) { MonthSwitcher() } }   // in the detail column so it isn't collapsed into »
        }
        .sheet(isPresented: $newEmployee) { EmployeeEditor(emp: nil) }
        .onReceive(NotificationCenter.default.publisher(for: .newEmployee)) { _ in newEmployee = true }
        .onReceive(NotificationCenter.default.publisher(for: .showSummary)) { _ in route = .summary }
        .onReceive(NotificationCenter.default.publisher(for: .openRoute)) { n in
            // shaon://summary, shaon://employee/<id>
            guard let url = n.object as? URL else { return }
            if url.host() == "employee", let id = url.pathComponents.dropFirst().first, model.emp(id) != nil { route = .employee(id) }
            else { route = .summary }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openEmployee)) { if let id = $0.object as? String { route = .employee(id) } }
        .onReceive(NotificationCenter.default.publisher(for: .exportExcel)) { _ in Exporter.excel(model) }
        .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in Exporter.savePDF(model) }
        .onReceive(NotificationCenter.default.publisher(for: .printReport)) { _ in Exporter.printReport(model) }
    }

    private func shown(_ ids: [String], _ byId: [String: Employee]) -> [Employee] {
        ids.compactMap { byId[$0] }.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    /// Right-click menu: pin / unpin and move (drag & drop in the list does the same).
    @ViewBuilder private func menu(_ e: Employee, _ lay: EmpLayout) -> some View {
        let pinned = lay.pinned.contains(e.id)
        Button(pinned ? "ביטול נעיצה" : "נעיצה בראש הרשימה", systemImage: pinned ? "pin.slash" : "pin") {
            model.applyLayout(lay.togglingPin(e.id))
        }
        Divider()
        Button("פתיחה בחלון חדש") { openWindow(id: "employee", value: e.id) }
        Button("הזזה למעלה", systemImage: "arrow.up") { model.applyLayout(lay.moving(e.id, by: -1)) }
        Button("הזזה למטה", systemImage: "arrow.down") { model.applyLayout(lay.moving(e.id, by: 1)) }
    }
    private func filtered(active: Bool) -> [Employee] {
        (active ? model.visibleEmployees().filter(\.isActive) : (model.employees ?? []).filter { !$0.isActive })
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private func row(_ e: Employee, _ a: Agg?) -> some View {
        HStack {
            Avatar(name: e.name, size: 26)
            Text(e.name)
            if model.settings?.empPinned?.contains(e.id) == true {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.tint).help("נעוצה בראש הרשימה")
            }
            if model.openShift(of: e.id) != nil {
                Circle().fill(.green).frame(width: 8, height: 8).help("בעבודה עכשיו")
            }
            Spacer()
            if let a, !a.unpaidShifts.isEmpty { Text(fmtMoney(a.unpaid)).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            else if let a, a.allPaid { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
    }
}

struct DeniedView: View {
    @Environment(AuthService.self) private var auth: AuthService?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 44)).foregroundStyle(.red)
            Text("אין הרשאה").font(.title.weight(.bold))
            if let auth, case .signedIn(_, _, let email) = auth.state { Text("החשבון \(email) לא מורשה לגשת למערכת.").foregroundStyle(.secondary) }
            Button("התחברות עם חשבון אחר") { auth?.signOut() }.buttonStyle(.borderedProminent)
        }.padding(40)
    }
}

struct MonthSwitcher: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack {
            Button { model.month = shiftMonthBy(model.month, -1) } label: { Image(systemName: "chevron.right") }.help("חודש קודם (⌘])")
            Button(fmtMonth(model.month)) { model.month = currentMonth() }.help("חזרה לחודש הנוכחי (⌘T)")
            Button { model.month = shiftMonthBy(model.month, 1) } label: { Image(systemName: "chevron.left") }.help("חודש הבא (⌘[)")
        }
    }
}

struct Onboarding: View {
    let step: Int
    @Environment(AppModel.self) private var model
    @State private var rate = ""
    @State private var showEditor = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark").font(.system(size: 44)).foregroundStyle(.tint)
            if step == 1 {
                Text("ברוך הבא! נתחיל בתעריף").font(.title.weight(.bold))
                Text("מה התעריף השעתי הרגיל של העובדות? אפשר לשנות אותו בכל רגע.").foregroundStyle(.secondary)
                TextField("לדוגמה: 40", text: $rate).frame(width: 160).multilineTextAlignment(.center).onSubmit(go)
                if let error { Text(error).foregroundStyle(.red) }
                Button("המשך", action: go).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                Text("עכשיו נוסיף את העובדת הראשונה").font(.title.weight(.bold))
                Button("הוספת עובדת") { showEditor = true }.buttonStyle(.borderedProminent)
            }
        }
        .padding(40).frame(maxWidth: 420)
        .sheet(isPresented: $showEditor) { EmployeeEditor(emp: nil) }
    }
    private func go() {
        guard let r = parseRate(rate), !r.isNaN else { error = "צריך להזין תעריף, לדוגמה 40"; return }
        Task { await model.saveSettings { $0.defaultRate = r } }
    }
}

extension Notification.Name {
    static let newEmployee = Notification.Name("shaon.newEmployee")
    static let showSummary = Notification.Name("shaon.showSummary")
    static let openRoute = Notification.Name("shaon.openRoute")
    static let exportExcel = Notification.Name("shaon.exportExcel")
    static let exportPDF = Notification.Name("shaon.exportPDF")
    static let printReport = Notification.Name("shaon.printReport")
}
