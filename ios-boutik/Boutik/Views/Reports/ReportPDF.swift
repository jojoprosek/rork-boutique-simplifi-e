import SwiftUI
import Charts
import UIKit

/// Everything the printed report needs, computed by ReportsView.
struct ReportData {
    var businessName: String
    var address: String
    var phone: String
    var periodTitle: String
    var stats: Store.Stats
    var buckets: [(label: String, value: Double)]
    var topProducts: [(name: String, qty: Double, total: Double)]
    var byMethod: [(label: String, total: Double)]
    var expenses: [(label: String, total: Double)]
    var sales: [Sale]
}

enum ReportPDF {
    static let pageWidth: CGFloat = 595 // A4
    static let pageHeight: CGFloat = 842

    @MainActor
    static func make(_ data: ReportData) -> URL? {
        let renderer = ImageRenderer(content: ReportPaper(data: data).frame(width: pageWidth))
        renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        let safeTitle = data.periodTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Rapport-\(safeTitle).pdf")
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            let pages = max(1, Int((size.height / pageHeight).rounded(.up)))
            for i in 0..<pages {
                ctx.beginPDFPage(nil)
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(box)
                ctx.saveGState()
                // Shift the tall content so page i shows its own slice, top first.
                ctx.translateBy(x: 0, y: pageHeight - size.height + CGFloat(i) * pageHeight)
                draw(ctx)
                ctx.restoreGState()
                ctx.endPDFPage()
            }
            ctx.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

/// Printable A4 report, always light so it prints well.
struct ReportPaper: View {
    let data: ReportData

    private let green = Color(red: 11 / 255, green: 122 / 255, blue: 62 / 255)
    private let coral = Color(red: 192 / 255, green: 53 / 255, blue: 31 / 255)
    private let ink = Color(red: 16 / 255, green: 24 / 255, blue: 40 / 255)
    private let grey = Color(red: 102 / 255, green: 112 / 255, blue: 133 / 255)
    private let line = Color(red: 228 / 255, green: 231 / 255, blue: 236 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            summary
            if data.buckets.contains(where: { $0.value > 0 }) { chart }
            HStack(alignment: .top, spacing: 16) {
                if !data.byMethod.isEmpty {
                    block("Comment on m'a payé", rows: data.byMethod.map { ($0.label, "", Fmt.money($0.total)) })
                }
                if !data.expenses.isEmpty {
                    block("Où part l'argent", rows: data.expenses.map { ($0.label, "", Fmt.money($0.total)) })
                }
            }
            if !data.topProducts.isEmpty {
                block("Ce qui se vend le plus", rows: data.topProducts.map { ($0.name, "\(Fmt.qty($0.qty)) vendus", Fmt.money($0.total)) })
            }
            if !data.sales.isEmpty { salesTable }
            Text("Rapport créé avec Boutik le \(Fmt.full.string(from: Date()))")
                .font(.system(size: 9))
                .foregroundStyle(grey)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .padding(40)
        .frame(width: ReportPDF.pageWidth, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(data.businessName).font(.system(size: 22, weight: .bold, design: .rounded))
                if !data.address.isEmpty { Text(data.address).font(.system(size: 10)).foregroundStyle(grey) }
                if !data.phone.isEmpty { Text("Tél : \(data.phone)").font(.system(size: 10)).foregroundStyle(grey) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("RAPPORT").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(grey)
                Text(data.periodTitle).font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 2) }
    }

    private var summary: some View {
        let s = data.stats
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Il me reste").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(Fmt.money(s.left))
                    .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(s.left >= 0 ? green : coral)
            }
            HStack(spacing: 12) {
                stat("Vendu", Fmt.money(s.sold), green)
                stat("Dépensé", Fmt.money(s.spent), coral)
                stat("Ventes", "\(s.salesCount)", ink)
                stat("Panier moyen", s.salesCount > 0 ? Fmt.money(s.sold / Double(s.salesCount)) : "—", ink)
            }
            Text("Dépensé = coût des produits vendus (\(Fmt.money(s.costOfGoods))) + dépenses (\(Fmt.money(s.expenses))).")
                .font(.system(size: 9)).foregroundStyle(grey)
        }
        .padding(16)
        .background(Color(red: 244 / 255, green: 246 / 255, blue: 250 / 255), in: .rect(cornerRadius: 14))
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            title("Ventes")
            Chart(Array(data.buckets.enumerated()), id: \.offset) { _, b in
                BarMark(x: .value("Quand", b.label), y: .value("Vendu", b.value))
                    .foregroundStyle(green)
                    .clipShape(.rect(cornerRadius: 3))
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(collisionResolution: .greedy).font(.system(size: 8)) }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.amount(d)).font(.system(size: 8)) } }
                }
            }
            .frame(height: 150)
        }
    }

    private func title(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(grey)
    }

    private func block(_ t: String, rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title(t)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.0).font(.system(size: 11, weight: .medium))
                        if !r.1.isEmpty { Text(r.1).font(.system(size: 9)).foregroundStyle(grey) }
                        Spacer()
                        Text(r.2).font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                    .padding(.vertical, 6)
                    if i < rows.count - 1 { Rectangle().fill(line).frame(height: 0.5) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var salesTable: some View {
        let list = data.sales.sorted { $0.date > $1.date }
        let shown = list.prefix(60)
        return VStack(alignment: .leading, spacing: 6) {
            title("Ventes (\(list.count))")
            HStack {
                Text("N°").frame(width: 62, alignment: .leading)
                Text("Date").frame(width: 110, alignment: .leading)
                Text("Client")
                Spacer()
                Text("Reste dû").frame(width: 80, alignment: .trailing)
                Text("Total").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(grey)
            Rectangle().fill(ink).frame(height: 1)
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                HStack {
                    Text(s.numberLabel).frame(width: 62, alignment: .leading)
                    Text(Fmt.shortDate(s.date)).frame(width: 110, alignment: .leading)
                    Text(s.clientName).lineLimit(1)
                    Spacer()
                    Text(s.remaining > 0 ? Fmt.amount(s.remaining) : "").foregroundStyle(coral).frame(width: 80, alignment: .trailing)
                    Text(Fmt.amount(s.total)).fontWeight(.semibold).frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 10).monospacedDigit())
                .padding(.vertical, 4)
                .background(i.isMultiple(of: 2) ? Color.clear : Color(red: 248 / 255, green: 249 / 255, blue: 251 / 255))
            }
            if list.count > shown.count {
                Text("+ \(list.count - shown.count) autres ventes").font(.system(size: 9)).foregroundStyle(grey)
            }
        }
    }
}

/// System share sheet for a file generated on demand.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
