import SwiftUI

struct ProductsView: View {
    @Environment(Store.self) private var store
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var showNew = false
    @State private var showScanner = false
    @State private var scanned: Product?
    @State private var showMassPrice = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tous", low = "Stock bas", archived = "Archivés"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        tile("Valeur du stock", Fmt.money(store.stockValueAtCost), sub: "au prix d'achat")
                        tile("Si tout est vendu", Fmt.money(store.stockValueAtPrice), sub: "au prix de vente")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section {
                    Picker("Filtre", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section {
                    if products.isEmpty {
                        EmptyStateView(icon: "shippingbox", title: "Aucun produit", message: "Ajoutez vos produits avec le bouton +.")
                    }
                    ForEach(products) { p in
                        NavigationLink { ProductDetailView(productId: p.id) } label: { ProductRow(product: p) }
                            .swipeActions(edge: .leading) {
                                Button { store.toggleFavorite(p) } label: { Label("Favori", systemImage: p.isFavorite ? "star.slash" : "star") }
                                    .tint(.orange)
                            }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.canvas.ignoresSafeArea())
            .searchable(text: $search, prompt: "Nom, code-barres, référence")
            .navigationTitle("Produits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                        .accessibilityLabel("Scanner un produit")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showNew = true } label: { Label("Nouveau produit", systemImage: "plus") }
                        NavigationLink { InventoryView() } label: { Label("Faire l'inventaire", systemImage: "checklist") }
                        Button { showMassPrice = true } label: { Label("Changer les prix en masse", systemImage: "percent") }
                        ShareLink(item: CSVExport.products(store: store)) { Label("Exporter (CSV)", systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew) { NavigationStack { ProductFormView(product: nil) } }
            .sheet(isPresented: $showMassPrice) { MassPriceSheet() }
            .fullScreenCover(isPresented: $showScanner) {
                BarcodeScannerView { code in
                    scanned = store.data.products.first { $0.barcode == code }
                    if scanned == nil { pendingBarcode = code; showNewWithCode = true }
                }
            }
            .navigationDestination(item: $scanned) { p in ProductDetailView(productId: p.id) }
            .sheet(isPresented: $showNewWithCode) {
                NavigationStack { ProductFormView(product: nil, barcode: pendingBarcode) }
            }
            .safeAreaPadding(.bottom, 60)
        }
    }

    @State private var pendingBarcode = ""
    @State private var showNewWithCode = false

    private var products: [Product] {
        var list: [Product]
        switch filter {
        case .all: list = store.activeProducts
        case .low: list = store.lowStockProducts
        case .archived: list = store.data.products.filter(\.isArchived)
        }
        let q = search.lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) || $0.barcode.contains(q) || $0.reference.lowercased().contains(q) }
        }
        return list.sorted { $0.name < $1.name }
    }

    private func tile(_ title: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
            Text(value).font(.money(19, weight: .heavy)).foregroundStyle(Color.gain).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption).foregroundStyle(Color.inkSecondary)
        }
        .card(radius: 22, padding: 14)
    }
}

struct ProductRow: View {
    @Environment(Store.self) private var store
    let product: Product

    var body: some View {
        let qty = store.stockOf(product.id)
        let low = store.isLow(product)
        HStack(spacing: 12) {
            ProductThumb(product: product, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(product.name).font(.headline).foregroundStyle(Color.ink).lineLimit(1)
                    if product.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                }
                Text(Fmt.money(product.retailPrice)).font(.subheadline.monospacedDigit()).foregroundStyle(Color.gain)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.qty(qty)).font(.money(18)).foregroundStyle(low ? Color.loss : Color.ink)
                Text(low ? "Presque fini" : product.unitName).font(.caption2.weight(.semibold))
                    .foregroundStyle(low ? Color.loss : Color.inkSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LowStockView: View {
    @Environment(Store.self) private var store
    @State private var category: String? = nil
    @State private var showOrder = false

    private var low: [Product] { store.lowStockProducts }
    private var categories: [String] {
        Array(Set(low.map(\.category))).sorted { $0.localizedCompare($1) == .orderedAscending }
    }
    private var shown: [Product] {
        guard let category else { return low }
        return low.filter { $0.category == category }
    }

    var body: some View {
        List {
            if categories.count > 1 {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            chip(nil, label: "Toutes", count: low.count)
                            ForEach(categories, id: \.self) { c in
                                chip(c, label: c, count: low.filter { $0.category == c }.count)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                if shown.isEmpty {
                    EmptyStateView(icon: "checkmark.seal", title: "Rien à signaler",
                                   message: category == nil ? "Aucun produit n'est presque fini." : "Aucun produit presque fini dans « \(category!) ».")
                        .listRowBackground(Color.clear)
                }
                ForEach(shown) { p in
                    NavigationLink { ProductDetailView(productId: p.id) } label: { ProductRow(product: p) }
                        .swipeActions(edge: .trailing) {
                            Button { store.addToOrder(p); showOrder = true } label: { Label("Commander", systemImage: "cart.badge.plus") }
                                .tint(.warn)
                        }
                }
            } footer: {
                Text(store.data.settings.stockAlertThreshold.map { "Un produit apparaît ici quand il en reste \(Fmt.qty($0)) ou moins." }
                     ?? "Un produit apparaît ici quand son stock passe sous son seuil d'alerte.")
            }
        }
        .animation(.snappy, value: category)
        .onChange(of: categories) { _, cats in
            if let c = category, !cats.contains(c) { category = nil }
        }
        .navigationTitle("Presque finis")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if !shown.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        for p in shown where !store.orderLines.contains(where: { $0.productId == p.id }) { store.addToOrder(p) }
                        showOrder = true
                    } label: {
                        Label("Tout commander", systemImage: "cart.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showOrder) { OrderListSheet() }
    }

    private func chip(_ value: String?, label: String, count: Int) -> some View {
        let selected = category == value
        return Button {
            category = value
            Haptics.tap()
        } label: {
            HStack(spacing: 6) {
                Text(label)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(selected ? Color.warn.opacity(0.15) : Color.chip, in: .capsule)
            }
            .font(.subheadline.weight(selected ? .bold : .medium))
            .foregroundStyle(selected ? Color.warn : Color.ink)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(selected ? Color.warnSoft : Color.card, in: .capsule)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }
}

struct MassPriceSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var percent: Double = 5
    @State private var category = "Tous"

    var body: some View {
        NavigationStack {
            Form {
                Picker("Catégorie", selection: $category) {
                    Text("Tous").tag("Tous")
                    ForEach(store.categories, id: \.self) { Text($0).tag($0) }
                }
                Stepper("Variation : \(percent >= 0 ? "+" : "")\(Int(percent)) %", value: $percent, in: -50...100, step: 1)
                Section {
                    Text("Les prix de détail et de gros seront arrondis à 25 près.").foregroundStyle(Color.inkSecondary)
                }
            }
            .navigationTitle("Prix en masse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        let factor = 1 + percent / 100
                        for var p in store.activeProducts where category == "Tous" || p.category == category {
                            p.retailPrice = ((p.retailPrice * factor) / 25).rounded() * 25
                            p.wholesalePrice = ((p.wholesalePrice * factor) / 25).rounded() * 25
                            store.saveProduct(p)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

enum CSVExport {
    static func products(store: Store) -> String {
        var s = "Nom;Catégorie;Code-barres;Unité;Prix d'achat;Prix détail;Prix gros;Stock\n"
        for p in store.data.products {
            s += "\(p.name);\(p.category);\(p.barcode);\(p.unitName);\(Int(p.costPrice));\(Int(p.retailPrice));\(Int(p.wholesalePrice));\(Fmt.qty(store.stockOf(p.id)))\n"
        }
        return s
    }

    static func sales(store: Store) -> String {
        var s = "Numéro;Date;Client;Total;Payé;Reste;Annulée\n"
        for v in store.data.sales {
            s += "\(v.numberLabel);\(Fmt.full.string(from: v.date));\(v.clientName);\(Int(v.total));\(Int(v.paid));\(Int(v.remaining));\(v.isCancelled ? "oui" : "non")\n"
        }
        return s
    }

    static func clients(store: Store) -> String {
        var s = "Nom;Téléphone;Adresse;Groupe;Limite;Doit\n"
        for c in store.data.clients {
            s += "\(c.name);\(c.phone);\(c.address);\(c.group.label);\(Int(c.creditLimit));\(Int(store.clientBalance(c.id)))\n"
        }
        return s
    }

    static func expenses(store: Store) -> String {
        var s = "Date;Catégorie;Note;Montant;Compte\n"
        for e in store.data.expenses {
            s += "\(Fmt.full.string(from: e.date));\(e.category);\(e.note);\(Int(e.amount));\(store.account(e.accountId)?.name ?? "")\n"
        }
        return s
    }
}
