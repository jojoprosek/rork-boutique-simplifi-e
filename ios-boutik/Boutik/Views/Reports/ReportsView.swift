import SwiftUI
import Charts

struct ReportsView: View {
    @Environment(Store.self) private var store
    @State private var period: Period
    @State private var offset = 0
    @State private var showPDF = false

    init(initial: Period = .today) { _period = State(initialValue: initial) }

    private var interval: DateInterval { period.interval(offset: offset) }
    private var sales: [Sale] { calc.sales }

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
                    Button { showPDF = true } label: {
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
        .fullScreenCover(isPresented: $showPDF) {
            ReportPDFPreview(period: period == .year ? .month : period, offset: period == .year ? 0 : offset)
        }
    }

    private var calc: ReportCalc { ReportCalc(store: store, period: period, offset: offset) }
    private var title: String { calc.title }
    private var buckets: [ReportBucket] { calc.buckets }

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

    private var topProducts: [ReportTop] { calc.topProducts }
    private var byMethod: [(PaymentMethod, Double)] { calc.byMethod }
    private var expensesByCat: [(String, Double)] { calc.expensesByCat }

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
