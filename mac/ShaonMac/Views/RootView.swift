import SwiftUI

enum Route: Hashable { case summary, employee(String) }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var route: Route? = .summary
    @State private var newEmployee = false
    @State private var search = ""

    var body: some View {
        Group {
            if !model.isLoaded { ProgressView("טוען…") }
            else if model.defaultRate == nil { Onboarding(step: 1) }
            else if model.visibleEmployees().isEmpty && (model.employees ?? []).isEmpty { Onboarding(step: 2) }
            else { main }
        }
        .onAppear { model.undoManager = undoManager }
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
                Section("עובדות") {
                    ForEach(filtered(active: true)) { e in row(e, agg[e.id]).tag(Route.employee(e.id)) }
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
            switch route ?? .summary {
            case .summary: SummaryView { route = .employee($0) }
            case .employee(let id): EmployeeView(empId: id).id(id)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Button { model.month = shiftMonthBy(model.month, -1) } label: { Image(systemName: "chevron.right") }.help("חודש קודם (⌘])")
                Button(fmtMonth(model.month)) { model.month = currentMonth() }.help("חזרה לחודש הנוכחי (⌘T)")
                Button { model.month = shiftMonthBy(model.month, 1) } label: { Image(systemName: "chevron.left") }.help("חודש הבא (⌘[)")
            }
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
    }

    private func filtered(active: Bool) -> [Employee] {
        model.visibleEmployees().filter { $0.isActive == active && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    private func row(_ e: Employee, _ a: Agg?) -> some View {
        HStack {
            Avatar(name: e.name, size: 26)
            Text(e.name)
            Spacer()
            if let a, !a.shifts.isEmpty, a.unpaid > 0 { Text(fmtMoney(a.unpaid)).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            else if let a, !a.shifts.isEmpty { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
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
}
