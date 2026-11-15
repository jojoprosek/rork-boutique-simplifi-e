import SwiftUI

struct ProductDetailView: View {
    @Environment(Store.self) private var store
    let productId: UUID

    @State private var movementMode: MovementMode?
    @State private var showEdit = false
    @State private var showCount = false
    @State private var confirmArchive = false

    enum MovementMode: String, Identifiable { case entry, exit; var id: String { rawValue } }

    var body: some View {
        Group {
            if let p = store.product(productId) {
                content(p)
            } else {
                EmptyStateView(icon: "shippingbox", title: "Produit introuvable", message: "")
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
    }

    private func content(_ p: Product) -> some View {
        let qty = store.stockOf(p.id)
        let showCosts = true
        return ScrollView {
            VStack(spacing: 14) {
                ProductPhoto(product: p)
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(p.category.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                    Text(p.name).font(.title2.bold()).foregroundStyle(Color.ink)
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.money(p.retailPrice)).font(.money(30, weight: .heavy)).foregroundStyle(Color.gain)
                        Text("/ \(p.unitName)").foregroundStyle(Color.inkSecondary)
                    }
                    if store.data.settings.businessType != .retail {
                        Text("Gros : \(Fmt.money(p.wholesalePrice))\(p.hasPack ? " · 1 \(p.packName) = \(Fmt.qty(p.packSize)) \(p.unitName)" : "")")
                            .font(.subheadline).foregroundStyle(Color.inkSecondary)
                    }
                }
                .card(radius: 26)

                HStack(spacing: 10) {
                    stockTile(title: "Il reste", value: "\(Fmt.qty(qty))", sub: p.unitName, color: qty <= p.lowStockAlert ? .loss : .ink)
                    if showCosts {
                        stockTile(title: "Je gagne", value: Fmt.amount(p.margin), sub: "\(Int(p.marginPercent.rounded())) % par \(p.unitName)", color: .gain)
                    }
                }

                HStack(spacing: 10) {
                    Button { movementMode = .entry } label: { Label("Entrée", systemImage: "tray.and.arrow.down") }
                        .buttonStyle(BigButtonStyle(kind: .green))
                    Button { movementMode = .exit } label: { Label("Sortie", systemImage: "tray.and.arrow.up") }
                        .buttonStyle(BigButtonStyle(kind: .outline))
                }
                Button { showCount = true } label: { Label("Compter le stock", systemImage: "checklist") }
                    .buttonStyle(BigButtonStyle(kind: .outline))

                details(p)
                movements(p)
            }
            .padding(16)
        }
        .navigationTitle(p.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showEdit = true } label: { Label("Modifier", systemImage: "pencil") }
                    Button { store.toggleFavorite(p) } label: { Label(p.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: "star") }
                    Button(role: p.isArchived ? nil : .destructive) {
                        if p.isArchived { store.setArchived(p, false) } else { confirmArchive = true }
                    } label: { Label(p.isArchived ? "Réactiver" : "Archiver", systemImage: "archivebox") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $movementMode) { mode in StockMovementSheet(product: p, isEntry: mode == .entry) }
        .sheet(isPresented: $showEdit) { NavigationStack { ProductFormView(product: p) } }
        .sheet(isPresented: $showCount) { CountSheet(product: p) }
        .confirmationDialog("Archiver « \(p.name) » ?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archiver", role: .destructive) { store.setArchived(p, true) }
        } message: { Text("Il ne sera plus proposé à la vente. Son historique est conservé.") }
    }

    private func stockTile(title: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.inkSecondary)
            Text(value).font(.money(28, weight: .heavy)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption).foregroundStyle(Color.inkSecondary)
        }
        .card(radius: 22, padding: 16)
    }

    private func details(_ p: Product) -> some View {
        VStack(spacing: 0) {
            row("Prix d'achat (coût moyen)", Fmt.money(p.costPrice))
            Divider()
            row("Seuil d'alerte", "\(Fmt.qty(p.lowStockAlert)) \(p.unitName)")
            if !p.barcode.isEmpty { Divider(); row("Code-barres", p.barcode) }
            if !p.reference.isEmpty { Divider(); row("Référence", p.reference) }
            ForEach(p.tiers) { t in
                Divider()
                row("Dès \(Fmt.qty(t.minQty)) \(p.unitName)", Fmt.money(t.price))
            }
            Divider()
            row("Valeur en stock", Fmt.money(max(0, store.stockOf(p.id)) * p.costPrice))
        }
        .padding(.horizontal, 16)
        .background(Color.card, in: .rect(cornerRadius: 24, style: .continuous))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.inkSecondary)
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(Color.ink)
        }
        .font(.subheadline)
        .frame(minHeight: 48)
    }

    private func movements(_ p: Product) -> some View {
        let list = store.data.movements.filter { $0.productId == p.id }.sorted { $0.date > $1.date }.prefix(25)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Mouvements de stock")
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                    HStack(spacing: 12) {
                        IconBadge(systemName: m.quantity >= 0 ? "arrow.down.left" : "arrow.up.right",
                                  tint: m.quantity >= 0 ? .gain : .loss, fill: m.quantity >= 0 ? .gainSoft : .lossSoft, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.kind.label + (m.note.isEmpty ? "" : " · \(m.note)")).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(Fmt.full.string(from: m.date)) · \(m.user)").font(.caption).foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                        Text(Fmt.signed(m.quantity).replacingOccurrences(of: "\u{202F}", with: ""))
                            .font(.money(16)).foregroundStyle(m.quantity >= 0 ? Color.gain : Color.loss)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 56)
                    if i < list.count - 1 { Divider().padding(.leading, 62) }
                }
            }
            .background(Color.card, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }
}

// MARK: - Stock movements

struct StockMovementSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let product: Product
    let isEntry: Bool

    @State private var kind: MovementKind = .purchase
    @State private var quantity: Double = 1
    @State private var usePack = false
    @State private var costText = ""
    @State private var payment: PayChoice = .account
    @State private var accountId: UUID?
    @State private var creditor = ""
    @State private var note = ""

    enum PayChoice: String, CaseIterable { case account, credit, none }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(isEntry ? MovementKind.entries : MovementKind.exits, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    HStack {
                        Text("Quantité")
                        Spacer()
                        QuantityStepper(value: $quantity)
                    }
                    if product.hasPack {
                        Toggle("En \(product.packName) (× \(Fmt.qty(product.packSize)))", isOn: $usePack)
                    }
                    LabeledContent("Total", value: "\(Fmt.qty(baseQty)) \(product.unitName)")
                }
                if isEntry && kind == .purchase {
                    Section("Achat") {
                        LabeledContent("Prix d'achat / \(product.unitName)") {
                            TextField(Fmt.amount(product.costPrice), text: $costText)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Montant", value: Fmt.money(baseQty * unitCost))
                        Picker("Payé", selection: $payment) {
                            Text("Payé").tag(PayChoice.account)
                            Text("À crédit").tag(PayChoice.credit)
                            Text("Déjà noté").tag(PayChoice.none)
                        }
                        .pickerStyle(.segmented)
                        if payment == .account {
                            Picker("Avec", selection: Binding(get: { accountId ?? store.data.accounts.first?.id }, set: { accountId = $0 })) {
                                ForEach(store.data.accounts) { Text($0.name).tag(Optional($0.id)) }
                            }
                        } else if payment == .credit {
                            TextField("Fournisseur", text: $creditor)
                        }
                    }
                }
                Section { TextField("Note (facultatif)", text: $note) }
            }
            .navigationTitle(isEntry ? "Entrée de stock" : "Sortie de stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        let isPurchase = isEntry && kind == .purchase
                        store.addMovement(product: product, quantity: baseQty, kind: kind,
                                          unitCost: isPurchase ? unitCost : nil,
                                          paidFrom: isPurchase && payment == .account ? (accountId ?? store.data.accounts.first?.id) : nil,
                                          onCreditTo: isPurchase && payment == .credit ? creditor : nil,
                                          note: note)
                        dismiss()
                    }
                    .disabled(quantity <= 0 || (isEntry && kind == .purchase && payment == .credit && creditor.isEmpty))
                }
            }
            .onAppear { kind = isEntry ? .purchase : .loss }
        }
    }

    private var baseQty: Double { usePack ? quantity * product.packSize : quantity }
    private var unitCost: Double { costText.isEmpty ? product.costPrice : Fmt.parse(costText) }
}

struct CountSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let product: Product
    @State private var counted: Double = 0

    var body: some View {
        let expected = store.stockOf(product.id)
        NavigationStack {
            Form {
                LabeledContent("Selon l'application", value: "\(Fmt.qty(expected)) \(product.unitName)")
                HStack {
                    Text("J'ai compté")
                    Spacer()
                    TextField("0", value: $counted, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).font(.money(20))
                        .frame(width: 120)
                }
                let diff = counted - expected
                LabeledContent("Écart") {
                    Text(diff == 0 ? "Aucun" : Fmt.signed(diff)).foregroundStyle(diff == 0 ? Color.gain : Color.loss).font(.headline)
                }
            }
            .navigationTitle("Compter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") { store.recordCount(product: product, counted: counted); dismiss() }
                }
            }
            .onAppear { counted = max(0, expected) }
        }
        .presentationDetents([.medium])
    }
}

struct InventoryView: View {
    @Environment(Store.self) private var store
    @State private var counts: [UUID: Double] = [:]
    @State private var showScanner = false
    @State private var done = false

    var body: some View {
        List {
            Section {
                Button { showScanner = true } label: { Label("Scanner un produit (+1)", systemImage: "barcode.viewfinder") }
            } footer: {
                Text("Comptez chaque produit. L'écart sera enregistré dans l'historique.")
            }
            ForEach(store.activeProducts) { p in
                HStack(spacing: 12) {
                    ProductThumb(product: p, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.subheadline.weight(.semibold))
                        let diff = (counts[p.id] ?? store.stockOf(p.id)) - store.stockOf(p.id)
                        Text("Prévu \(Fmt.qty(store.stockOf(p.id)))\(diff != 0 ? " · écart \(Fmt.signed(diff))" : "")")
                            .font(.caption).foregroundStyle(diff == 0 ? Color.inkSecondary : Color.loss)
                    }
                    Spacer()
                    TextField("0", value: Binding(get: { counts[p.id] ?? store.stockOf(p.id) }, set: { counts[p.id] = $0 }), format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .font(.money(18)).frame(width: 70)
                }
            }
        }
        .navigationTitle("Inventaire")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    for (id, c) in counts { if let p = store.product(id) { store.recordCount(product: p, counted: c) } }
                    counts = [:]
                    done = true
                }
                .disabled(counts.isEmpty)
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            BarcodeScannerView { code in
                if let p = store.activeProducts.first(where: { $0.barcode == code }) {
                    counts[p.id] = (counts[p.id] ?? 0) + 1
                }
            }
        }
        .alert("Inventaire enregistré", isPresented: $done) { Button("OK") {} }
    }
}

struct StockInPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Product?
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(store.activeProducts.filter { search.isEmpty || $0.name.lowercased().contains(search.lowercased()) }) { p in
                Button { selected = p } label: { ProductRow(product: p) }
                    .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Quel produit ?")
            .navigationTitle("Entrée de stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .sheet(item: $selected) { p in StockMovementSheet(product: p, isEntry: true) }
        }
    }
}
