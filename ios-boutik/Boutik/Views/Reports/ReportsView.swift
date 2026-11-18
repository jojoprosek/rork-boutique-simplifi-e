import SwiftUI
import Charts

struct ReportsView: View {
    @Environment(Store.self) private var store
    @State private var period: Period
    @State private var offset = 0
    @State private var pdfURL: URL?
    @State private var showPDF = false
    @State private var pdfFailed = false

    init(initial: Period = .today) { _period = State(initialValue: initial) }

    private var interval: DateInterval { period.interval(offset: offset) }
    private var sales: [Sale] { store.data.sales.filter { !$0.isCancelled && interval.contains($0.date) } }

    var body: some View {
        let stats = store.stats(interval)
        ScrollView {
            VStack(spacing: 14) {
                Picker("Période", selection: $period) {
                    ForEach(Period.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _, _ in offset = 0 }

                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    Spacer()
                    Text(title).font(.headline).foregroundStyle(Color.ink)
                    Spacer()
                    Button { offset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(offset >= 0)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Il me reste").font(.title3.weight(.semibold))
                    Text(Fmt.money(stats.left)).font(.money(40, weight: .heavy))
                        .foregroundStyle(stats.left >= 0 ? Color.gain : Color.loss)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    HStack(spacing: 10) {
                        mini("Vendu", stats.sold, .gain)
                        mini("Dépensé", stats.spent, .loss)
                    }
                    Text("Dépensé = coût des produits vendus (\(Fmt.money(stats.costOfGoods))) + dépenses (\(Fmt.money(stats.expenses))).")
                        .font(.caption).foregroundStyle(Color.inkSecondary)
                }
                .card(radius: 28)

                chart

                HStack(spacing: 10) {
                    tile("Ventes", "\(stats.salesCount)")
                    tile("Panier moyen", stats.salesCount > 0 ? Fmt.amount(stats.sold / Double(stats.salesCount)) : "0")
                }

                if !topProducts.isEmpty {
                    SectionHeader(title: "Ce qui se vend le plus")
                    listCard(topProducts.map { ($0.name, "\(Fmt.qty($0.qty)) vendus", Fmt.money($0.total)) })
                }
                if !byMethod.isEmpty {
                    SectionHeader(title: "Comment on m'a payé")
                    listCard(byMethod.map { ($0.0.label, "", Fmt.money($0.1)) })
                }
                if !expensesByCat.isEmpty {
                    SectionHeader(title: "Où part l'argent")
                    listCard(expensesByCat.map { ($0.0, "", Fmt.money($0.1)) })
                }
                if !sales.isEmpty {
                    SectionHeader(title: "Ventes")
                    VStack(spacing: 0) {
                        ForEach(sales.sorted { $0.date > $1.date }.prefix(30)) { s in
                            NavigationLink { SaleDetailView(saleId: s.id) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.clientName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                                        Text("\(s.numberLabel) · \(Fmt.shortDate(s.date))").font(.caption).foregroundStyle(Color.inkSecondary)
                                    }
                                    Spacer()
                                    Text(Fmt.money(s.total)).font(.money(15)).foregroundStyle(Color.ink)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.inkSecondary)
                                }
                                .padding(.horizontal, 16).frame(minHeight: 54)
                            }
                        }
                    }
                    .background(Color.card, in: .rect(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle("Rapports")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { exportPDF(stats) } label: {
                        Label("Rapport PDF", systemImage: "doc.richtext")
                    }
                    ShareLink(item: summaryText(stats)) {
                        Label("Partager le résumé", systemImage: "text.alignleft")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Partager le rapport")
            }
        }
        .sheet(isPresented: $showPDF) {
            if let pdfURL {
                ShareSheet(items: [pdfURL])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
        .alert("Impossible de créer le PDF", isPresented: $pdfFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Réessayez dans un instant.") }
    }

    private func exportPDF(_ stats: Store.Stats) {
        let s = store.data.settings
        let data = ReportData(
            businessName: s.businessName, address: s.address, phone: s.phone,
            periodTitle: title, stats: stats,
            buckets: buckets.map { ($0.label, $0.value) },
            topProducts: topProducts.map { ($0.name, $0.qty, $0.total) },
            byMethod: byMethod.map { ($0.0.label, $0.1) },
            expenses: expensesByCat.map { ($0.0, $0.1) },
            sales: sales)
        if let url = ReportPDF.make(data) {
            pdfURL = url
            Haptics.success()
            showPDF = true
        } else {
            Haptics.warning()
            pdfFailed = true
        }
    }

    private var title: String {
        switch period {
        case .today: return Fmt.day.string(from: interval.start).capitalized
        case .week: return "Semaine du \(Fmt.dayMonth.string(from: interval.start))"
        case .month:
            let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "LLLL yyyy"
            return f.string(from: interval.start).capitalized
        case .year: return String(Calendar.current.component(.year, from: interval.start))
        }
    }

    // MARK: Chart

    private struct Bucket: Identifiable { let id: Int; let label: String; let value: Double }

    private var buckets: [Bucket] {
        let cal = Calendar.current
        switch period {
        case .today:
            return stride(from: 6, through: 22, by: 2).map { h in
                let v = sales.filter { let x = cal.component(.hour, from: $0.date); return x >= h && x < h + 2 }.reduce(0) { $0 + $1.total }
                return Bucket(id: h, label: "\(h)h", value: v)
            }
        case .week, .month:
            let days = cal.dateComponents([.day], from: interval.start, to: interval.end).day ?? 7
            let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = period == .week ? "EEE" : "d"
            return (0..<days).map { i in
                let d = cal.date(byAdding: .day, value: i, to: interval.start)!
                let v = sales.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.total }
                return Bucket(id: i, label: f.string(from: d), value: v)
            }
        case .year:
            let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "MMM"
            return (0..<12).map { m in
                let d = cal.date(byAdding: .month, value: m, to: interval.start)!
                let v = sales.filter { cal.component(.month, from: $0.date) == m + 1 }.reduce(0) { $0 + $1.total }
                return Bucket(id: m, label: f.string(from: d), value: v)
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ventes").font(.headline)
            Chart(buckets) { b in
                BarMark(x: .value("Quand", b.label), y: .value("Vendu", b.value))
                    .foregroundStyle(Color.gain.gradient)
                    .clipShape(.rect(cornerRadius: 5))
            }
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel(collisionResolution: .greedy)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(short(d)) } }
                }
            }
            .frame(height: 180)
        }
        .card(radius: 26)
    }

    private func short(_ v: Double) -> String {
        v >= 1_000_000 ? "\(Fmt.qty((v / 100_000).rounded() / 10))M" : v >= 1000 ? "\(Int(v / 1000))k" : "\(Int(v))"
    }

    // MARK: Aggregates

    private struct Top { let name: String; let qty: Double; let total: Double }

    private var topProducts: [Top] {
        var map: [UUID: (String, Double, Double)] = [:]
        for s in sales { for l in s.lines {
            let cur = map[l.productId] ?? (l.name, 0, 0)
            map[l.productId] = (l.name, cur.1 + l.baseQuantity, cur.2 + l.total)
        } }
        return map.values.map { Top(name: $0.0, qty: $0.1, total: $0.2) }.sorted { $0.total > $1.total }.prefix(5).map { $0 }
    }

    private var byMethod: [(PaymentMethod, Double)] {
        var map: [PaymentMethod: Double] = [:]
        for s in sales {
            for p in s.payments { map[p.method, default: 0] += p.amount }
            if s.remaining > 0 { map[.credit, default: 0] += s.remaining }
        }
        return map.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private var expensesByCat: [(String, Double)] {
        var map: [String: Double] = [:]
        for e in store.data.expenses where interval.contains(e.date) { map[e.category, default: 0] += e.amount }
        return map.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: Pieces

    private func mini(_ label: String, _ v: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(Fmt.money(v)).font(.money(17)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color == .gain ? Color.gainSoft : Color.lossSoft, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Color.inkSecondary)
            Text(value).font(.money(24, weight: .heavy)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.6)
        }
        .card(radius: 22, padding: 16)
    }

    private func listCard(_ rows: [(String, String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.0).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                        if !r.1.isEmpty { Text(r.1).font(.caption).foregroundStyle(Color.inkSecondary) }
                    }
                    Spacer()
                    Text(r.2).font(.money(15)).foregroundStyle(Color.ink)
                }
                .padding(.horizontal, 16).frame(minHeight: 52)
                if i < rows.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .background(Color.card, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func summaryText(_ s: Store.Stats) -> String {
        """
        \(store.data.settings.businessName) — \(title)
        Vendu : \(Fmt.money(s.sold))
        Dépensé : \(Fmt.money(s.spent))
        Il me reste : \(Fmt.money(s.left))
        Ventes : \(s.salesCount)
        """
    }
}
