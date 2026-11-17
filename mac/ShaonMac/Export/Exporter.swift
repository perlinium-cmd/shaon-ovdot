import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import libxlsxwriter

/// Month rows shared by Excel, PDF and print.
struct MonthReport {
    let month: String
    let rows: [(emp: Employee, agg: Agg)]
    // Sums in whole agorot, like everywhere else (never adding up rounded shekels).
    var totalPay: Double { Double(rows.reduce(0) { $0 + $1.agg.payAgorot }) / 100 }
    var totalPaid: Double { Double(rows.reduce(0) { $0 + $1.agg.paidAgorot }) / 100 }
    var totalUnpaid: Double { Double(rows.reduce(0) { $0 + $1.agg.payAgorot - $1.agg.paidAgorot }) / 100 }
    var totalMin: Int { rows.reduce(0) { $0 + $1.agg.minutes } }
    var totalShifts: Int { rows.reduce(0) { $0 + $1.agg.shifts.count } }

    @MainActor init(_ model: AppModel) {
        month = model.month
        let agg = model.agg
        rows = model.visibleEmployees().compactMap { e in agg[e.id].map { (e, $0) } }
    }
}

@MainActor
enum Exporter {
    // MARK: Excel
    static func excel(_ model: AppModel) {
        let report = MonthReport(model)
        guard !report.rows.isEmpty else { model.say("אין משמרות לייצוא"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]
        panel.nameFieldStringValue = "שעות-\(model.month).xlsx"
        panel.title = "ייצוא לאקסל"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try writeXLSX(report, model: model, to: url)
            model.say("הקובץ נשמר")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { model.fail(error) }
    }

    private static func writeXLSX(_ r: MonthReport, model: AppModel, to url: URL) throws {
        guard let wb = workbook_new(url.path) else { throw CocoaError(.fileWriteUnknown) }
        let bold = workbook_add_format(wb); format_set_bold(bold)
        let money = workbook_add_format(wb); format_set_num_format(money, "#,##0.00")
        let moneyBold = workbook_add_format(wb); format_set_num_format(moneyBold, "#,##0.00"); format_set_bold(moneyBold)
        func hours(_ m: Int) -> Double { round2(Double(m) / 60) }
        func str(_ ws: UnsafeMutablePointer<lxw_worksheet>?, _ row: Int, _ col: Int, _ v: String, _ f: UnsafeMutablePointer<lxw_format>? = nil) {
            worksheet_write_string(ws, lxw_row_t(row), lxw_col_t(col), v, f)
        }
        func num(_ ws: UnsafeMutablePointer<lxw_worksheet>?, _ row: Int, _ col: Int, _ v: Double, _ f: UnsafeMutablePointer<lxw_format>? = nil) {
            worksheet_write_number(ws, lxw_row_t(row), lxw_col_t(col), v, f)
        }

        // Summary sheet
        let ws = workbook_add_worksheet(wb, "סיכום")
        worksheet_right_to_left(ws)
        worksheet_set_column(ws, 0, 0, 18, nil); worksheet_set_column(ws, 1, 7, 14, nil)
        for (i, h) in ["עובדת", "משמרות", "שעות (עשרוני)", "שעות (ש:ד)", "תעריף לשעה", "סה״כ (₪)", "שולם (₪)", "נותר לתשלום (₪)"].enumerated() { str(ws, 0, i, h, bold) }
        for (i, row) in r.rows.enumerated() {
            let (e, a) = row, y = i + 1
            let rates = Set(a.shifts.map { shiftRate($0, e, defaultRate: model.defaultRate) })
            str(ws, y, 0, e.name); num(ws, y, 1, Double(a.shifts.count)); num(ws, y, 2, hours(a.minutes)); str(ws, y, 3, fmtHM(a.minutes))
            if rates.count == 1 { num(ws, y, 4, rates.first!) } else { str(ws, y, 4, "משתנה") }
            num(ws, y, 5, a.pay, money); num(ws, y, 6, a.paidPay, money); num(ws, y, 7, a.unpaid, money)
        }
        let t = r.rows.count + 2
        str(ws, t, 0, "סה״כ", bold); num(ws, t, 1, Double(r.totalShifts), bold); num(ws, t, 2, hours(r.totalMin), bold); str(ws, t, 3, fmtHM(r.totalMin), bold)
        num(ws, t, 5, r.totalPay, moneyBold); num(ws, t, 6, r.totalPaid, moneyBold); num(ws, t, 7, r.totalUnpaid, moneyBold)

        // One sheet per employee
        var used: Set<String> = ["סיכום"]
        for (e, a) in r.rows {
            var name = String(e.name.replacingOccurrences(of: "[\\[\\]:*?/\\\\]", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces).prefix(28))
            if name.isEmpty { name = "עובדת" }
            var n = 2; let base = name
            while used.contains(name) { name = "\(base.prefix(26)) \(n)"; n += 1 }
            used.insert(name)
            let sh = workbook_add_worksheet(wb, name)
            worksheet_right_to_left(sh)
            worksheet_set_column(sh, 0, 10, 13, nil)
            for (i, h) in ["תאריך", "יום", "כניסה", "יציאה", "שעות (עשרוני)", "שעות (ש:ד)", "תעריף לשעה", "תעריף מיוחד", "שעות בתעריף מיוחד", "סכום (₪)", "שולם"].enumerated() { str(sh, 0, i, h, bold) }
            let sorted = a.shifts.sorted { ($0.date, $0.in) < ($1.date, $1.in) }
            for (i, s) in sorted.enumerated() {
                let y = i + 1, min = shiftMinutes(s.date, s.in, s.out), d = parseDate(s.date)
                let c = gregorian.dateComponents([.day, .month, .year], from: d)
                str(sh, y, 0, String(format: "%02d/%02d/%d", c.day!, c.month!, c.year!)); str(sh, y, 1, fmtWeekday(s.date))
                str(sh, y, 2, model.fmt(s.in)); num(sh, y, 6, shiftRate(s, e, defaultRate: model.defaultRate))
                if s.isOpen { str(sh, y, 3, "עדיין במשמרת"); continue }   // running: no hours or pay yet
                str(sh, y, 3, model.fmt(s.out))
                num(sh, y, 4, hours(min)); str(sh, y, 5, fmtHM(min))
                if let sp = s.special?.rate { num(sh, y, 7, sp); num(sh, y, 8, hours(Int(specialMinutes(s)))) }
                num(sh, y, 9, model.pay(s), money); str(sh, y, 10, s.isPaid ? "כן" : "לא")
            }
            let ty = sorted.count + 2
            str(sh, ty, 0, "סה״כ", bold); num(sh, ty, 4, hours(a.minutes), bold); str(sh, ty, 5, fmtHM(a.minutes), bold)
            num(sh, ty, 9, a.pay, moneyBold); str(sh, ty, 10, "שולם \(fmtMoney(a.paidPay))", bold)
        }
        if workbook_close(wb) != LXW_NO_ERROR { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: PDF / print / share
    static func pdfData(_ model: AppModel) -> Data? {
        let view = ReportView(report: MonthReport(model)).environment(\.layoutDirection, .rightToLeft)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .init(width: 595, height: nil)
        let data = NSMutableData()
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 595, height: max(842, size.height))
            guard let consumer = CGDataConsumer(data: data as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            ctx.translateBy(x: (595 - size.width) / 2, y: box.height - size.height)   // top-aligned
            draw(ctx)
            ctx.endPDFPage(); ctx.closePDF()
        }
        return data.length > 0 ? data as Data : nil
    }

    static func savePDF(_ model: AppModel) {
        guard let data = pdfData(model) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "שעות-\(model.month).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url); model.say("ה-PDF נשמר"); NSWorkspace.shared.activateFileViewerSelecting([url]) } catch { model.fail(error) }
    }

    static func printReport(_ model: AppModel) {
        guard let data = pdfData(model), let doc = PDFDocument(data: data) else { return }
        let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        pdfView.document = doc
        pdfView.print(with: NSPrintInfo.shared, autoRotate: true)
    }

    /// Temp PDF for the share button.
    static func sharePDF(_ model: AppModel) -> URL? {
        guard let data = pdfData(model) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("שעות-\(model.month).pdf")
        return (try? data.write(to: url)) != nil ? url : nil
    }
}

struct ReportView: View {
    let report: MonthReport
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("שעון עובדות").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text("הופק ב-\(Date.now.formatted(date: .numeric, time: .omitted))").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("סיכום \(fmtMonth(report.month))").font(.system(size: 24, weight: .bold))
            HStack(spacing: 10) {
                box("נותר לתשלום", fmtMoney(report.totalUnpaid))
                box("שולם", fmtMoney(report.totalPaid))
                box("שעות", fmtHM(report.totalMin))
            }
            VStack(spacing: 0) {
                row(["עובדת", "משמרות", "שעות", "סה״כ", "שולם / נותר"], head: true)
                ForEach(report.rows, id: \.emp.id) { e, a in
                    Divider()
                    row([e.name, "\(a.shifts.count)", fmtHM(a.minutes), fmtMoney(a.pay), a.unpaid <= 0 ? "שולם ✓" : "נותר \(fmtMoney(a.unpaid))"])
                }
                Divider()
                row(["סה״כ", "\(report.totalShifts)", fmtHM(report.totalMin), fmtMoney(report.totalPay), fmtMoney(report.totalUnpaid)], head: true)
            }
        }
        .padding(36).frame(width: 595, alignment: .leading).background(.white).foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }
    private func box(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(l).font(.system(size: 10)).foregroundStyle(.gray); Text(v).font(.system(size: 16, weight: .bold)) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 8))
    }
    private func row(_ c: [String], head: Bool = false) -> some View {
        HStack {
            Text(c[0]).frame(maxWidth: .infinity, alignment: .leading)
            Text(c[1]).frame(width: 60, alignment: .leading)
            Text(c[2]).frame(width: 60, alignment: .leading)
            Text(c[3]).frame(width: 80, alignment: .leading)
            Text(c[4]).frame(width: 110, alignment: .leading)
        }.font(.system(size: 12, weight: head ? .semibold : .regular)).padding(.vertical, 6)
    }
}
