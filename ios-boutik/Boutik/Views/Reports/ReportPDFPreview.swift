import SwiftUI
import PDFKit

/// Two steps before sharing the PDF report: choose the period (réglages),
/// then check the real PDF and confirm the send.
struct ReportPDFPreview: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var period: Period
    @State private var offset: Int
    @State private var step: Step = .settings
    @State private var pdfURL: URL?
    @State private var showShare = false
    @State private var pdfFailed = false

    enum Step { case settings, preview }

    private static let periods: [Period] = [.today, .week, .month]

    init(period: Period, offset: Int) {
        _period = State(initialValue: Self.periods.contains(period) ? period : .month)
        _offset = State(initialValue: offset)
    }

    private var calc: ReportCalc { ReportCalc(store: store, period: period, offset: offset) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.canvas.ignoresSafeArea()
                switch step {
                case .settings:
                    settings
                        .transition(.move(edge: .leading).combined(with: .opacity))
                case .preview:
                    preview
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
            .navigationTitle(step == .settings ? "Rapport PDF" : "Aperçu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
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
    }

    // MARK: Step 1 — réglages

    private var settings: some View {
        let c = calc
        let stats = c.stats
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quelle période ?").font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
                    Picker("Période", selection: $period) {
                        Text("Jour").tag(Period.today)
                        Text("Semaine").tag(Period.week)
                        Text("Mois").tag(Period.month)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: period) { _, _ in offset = 0; Haptics.tap() }

                    HStack {
                        Button { offset -= 1; Haptics.tap() } label: {
                            Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Période précédente")
                        Spacer()
                        Text(c.title).font(.headline).foregroundStyle(Color.ink).contentTransition(.numericText())
                        Spacer()
                        Button { offset += 1; Haptics.tap() } label: {
                            Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                        }
                        .disabled(offset >= 0)
                        .accessibilityLabel("Période suivante")
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 4)
                    .background(Color.chip, in: .rect(cornerRadius: 16, style: .continuous))
                }
                .card(radius: 26)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Dans le rapport").font(.headline).foregroundStyle(Color.ink)
                    row("Vendu", Fmt.money(stats.sold), .gain, icon: "arrow.up.right")
                    row("Dépensé", Fmt.money(stats.spent), .loss, icon: "arrow.down.right")
                    row("Il me reste", Fmt.money(stats.left), stats.left >= 0 ? .gain : .loss, icon: "equal")
                    Divider()
                    Label("\(stats.salesCount) vente\(stats.salesCount > 1 ? "s" : "") · \(c.expensesByCat.count) catégorie\(c.expensesByCat.count > 1 ? "s" : "") de dépenses",
                          systemImage: "doc.text")
                        .font(.subheadline).foregroundStyle(Color.inkSecondary)
                    Label("Graphique des ventes par \(period == .today ? "heure" : "jour")", systemImage: "chart.bar")
                        .font(.subheadline).foregroundStyle(Color.inkSecondary)
                }
                .card(radius: 26)
                .animation(.snappy, value: c.title)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                makePDF()
            } label: {
                Label("Voir l'aperçu", systemImage: "doc.viewfinder")
            }
            .buttonStyle(BigButtonStyle(kind: .dark))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.canvas.opacity(0.95))
        }
    }

    private func row(_ label: String, _ value: String, _ color: Color, icon: String) -> some View {
        HStack {
            IconBadge(systemName: icon, tint: color, fill: color == .gain ? .gainSoft : .lossSoft, size: 34)
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
            Spacer()
            Text(value).font(.money(17)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(minHeight: 36)
    }

    // MARK: Step 2 — aperçu

    private var preview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "calendar").foregroundStyle(Color.gain)
                Text(calc.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                Spacer()
                Text("Vérifiez avant d'envoyer").font(.caption).foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if let pdfURL {
                PDFKitView(url: pdfURL)
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
                    .padding(.horizontal, 12)
                    .accessibilityLabel("Aperçu du rapport PDF")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    step = .settings
                    Haptics.tap()
                } label: {
                    Label("Réglages", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(BigButtonStyle(kind: .outline))
                .accessibilityLabel("Retour aux réglages")

                Button {
                    Haptics.success()
                    showShare = true
                } label: {
                    Label("Envoyer", systemImage: "paperplane.fill")
                }
                .buttonStyle(BigButtonStyle(kind: .green))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.canvas.opacity(0.95))
        }
    }

    private func makePDF() {
        if let url = ReportPDF.make(calc.reportData) {
            pdfURL = url
            Haptics.tap()
            step = .preview
        } else {
            Haptics.warning()
            pdfFailed = true
        }
    }
}

/// Read-only PDFKit viewer.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            view.autoScales = true
        }
    }
}
