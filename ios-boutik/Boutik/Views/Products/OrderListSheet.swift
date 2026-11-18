import SwiftUI

/// How the order list is sorted.
enum OrderSort: String, CaseIterable {
    case supplier, cost
    var label: String { self == .supplier ? "Fournisseur" : "Coût de ligne" }
}

/// Supplier order list, pre-filled with what is missing to get back to the alert threshold.
struct OrderListSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var onCredit = false
    @State private var accountId: UUID?
    @State private var supplier = ""
    @State private var confirmClear = false
    @AppStorage("orderSort") private var sort: OrderSort = .supplier
    @State private var supplierLine: OrderLine?
    @State private var newSupplier = ""

    private var lines: [OrderLine] { store.orderLines }

    /// Lines grouped for display. By supplier: A→Z, "Sans fournisseur" last, most expensive first inside.
    /// By cost: a single group, most expensive line first.
    private var groups: [(name: String?, lines: [OrderLine])] {
        let byCost: (OrderLine, OrderLine) -> Bool = { $0.lineCost == $1.lineCost ? productName($0) < productName($1) : $0.lineCost > $1.lineCost }
        switch sort {
        case .cost:
            return [(nil, lines.sorted(by: byCost))]
        case .supplier:
            let dict = Dictionary(grouping: lines) { $0.supplierName ?? "" }
            let names = dict.keys.filter { !$0.isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            var out = names.map { (name: Optional($0), lines: dict[$0]!.sorted(by: byCost)) }
            if let none = dict[""] { out.append((name: "Sans fournisseur", lines: none.sorted(by: byCost))) }
            return out
        }
    }

    private func productName(_ l: OrderLine) -> String { store.product(l.productId)?.name ?? "" }
    private var missingLow: [Product] {
        store.lowStockProducts.filter { p in !lines.contains { $0.productId == p.id } }
    }

    var body: some View {
        NavigationStack {
            List {
                if lines.isEmpty {
                    Section {
                        EmptyStateView(icon: "list.clipboard",
                                       title: "Liste vide",
                                       message: "Touchez « Commander » sur un produit presque fini pour l'ajouter ici.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        VStack(spacing: 12) {
                            totalHeader
                            sortPicker
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    let grouped = groups
                    ForEach(Array(grouped.enumerated()), id: \.offset) { index, group in
                        Section {
                            ForEach(group.lines) { line in
                                if let p = store.product(line.productId) {
                                    OrderLineRow(line: line, product: p, showSupplier: sort == .cost,
                                                 suppliers: store.knownSuppliers,
                                                 onPickSupplier: { name in store.setOrderSupplier(name, for: line) },
                                                 onNewSupplier: { newSupplier = line.supplier ?? ""; supplierLine = line })
                                }
                            }
                            .onDelete { idx in
                                store.removeFromOrder(idx.map { group.lines[$0].id })
                            }
                        } header: {
                            if let name = group.name {
                                HStack {
                                    Label(name, systemImage: name == "Sans fournisseur" ? "questionmark.circle" : "building.2")
                                    Spacer()
                                    Text(Fmt.money(group.lines.reduce(0) { $0 + $1.lineCost }))
                                        .font(.money(13))
                                }
                            } else {
                                Text("À commander · du plus cher au moins cher")
                            }
                        } footer: {
                            if index == grouped.count - 1 {
                                Text("Quantités calculées pour revenir au seuil d'alerte. Glissez une ligne vers la gauche pour la retirer.")
                            }
                        }
                    }
                }

                if !missingLow.isEmpty {
                    Section {
                        Button {
                            withAnimation(.snappy) { store.addAllLowToOrder() }
                        } label: {
                            Label(missingLow.count == 1 ? "Ajouter le produit presque fini" : "Ajouter les \(missingLow.count) produits presque finis",
                                  systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.gain)
                                .frame(minHeight: 36)
                        }
                    }
                }

                if !lines.isEmpty {
                    Section("Envoyer au fournisseur") {
                        Button {
                            if let url = ReceiptBuilder.whatsappURL(phone: nil, text: orderText) { openURL(url) }
                        } label: {
                            Label("Envoyer par WhatsApp", systemImage: "message.fill")
                                .foregroundStyle(Color.ink)
                                .frame(minHeight: 36)
                        }
                        ShareLink(item: orderText) {
                            Label("Partager la liste", systemImage: "square.and.arrow.up")
                                .foregroundStyle(Color.ink)
                                .frame(minHeight: 36)
                        }
                    }

                    Section {
                        Picker("Paiement", selection: $onCredit) {
                            Text("Payé maintenant").tag(false)
                            Text("À crédit").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: onCredit) { _, credit in
                            let names = Set(lines.compactMap(\.supplierName))
                            if credit, supplier.isEmpty, names.count == 1 { supplier = names.first! }
                        }
                        if onCredit {
                            TextField("Nom du fournisseur", text: $supplier)
                                .textInputAutocapitalization(.words)
                        } else {
                            AccountPicker(selection: $accountId)
                        }
                    } header: {
                        Text("La marchandise est arrivée ?")
                    } footer: {
                        Text(onCredit
                             ? "Le stock augmente et \(Fmt.money(store.orderTotal)) s'ajoute à « Je dois »."
                             : "Le stock augmente et \(Fmt.money(store.orderTotal)) sort du compte choisi.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.canvas)
            .animation(.snappy, value: lines.map(\.id))
            .animation(.snappy, value: sort)
            .alert("Fournisseur", isPresented: Binding(get: { supplierLine != nil }, set: { if !$0 { supplierLine = nil } })) {
                TextField("Nom du fournisseur", text: $newSupplier)
                    .textInputAutocapitalization(.words)
                Button("Annuler", role: .cancel) {}
                Button("Enregistrer") {
                    if let line = supplierLine { store.setOrderSupplier(newSupplier, for: line) }
                }
            } message: {
                Text("Il sera retenu pour ce produit lors des prochaines commandes.")
            }
            .navigationTitle("Liste de commande")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                if !lines.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Vider", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Vider la liste de commande ?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Vider la liste", role: .destructive) {
                    withAnimation(.snappy) { store.clearOrder() }
                    Haptics.warning()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !lines.isEmpty {
                    Button {
                        let account = onCredit ? nil : (accountId ?? store.data.accounts.first?.id)
                        let creditor = onCredit ? (supplier.trimmingCharacters(in: .whitespaces).isEmpty ? "Fournisseur" : supplier) : nil
                        store.receiveOrder(paidFrom: account, creditor: creditor)
                        dismiss()
                    } label: {
                        Label("Marquer comme reçue", systemImage: "shippingbox.fill")
                    }
                    .buttonStyle(BigButtonStyle(kind: .green))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        }
    }

    private var totalHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Coût estimé").font(.subheadline.weight(.medium)).foregroundStyle(Color.inkSecondary)
                Text(Fmt.money(store.orderTotal))
                    .font(.money(32, weight: .heavy))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
            }
            Spacer()
            Text(lines.count == 1 ? "1 produit" : "\(lines.count) produits")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.warn)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.warnSoft, in: .capsule)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .animation(.snappy, value: store.orderTotal)
    }

    private var sortPicker: some View {
        Picker("Trier par", selection: $sort) {
            ForEach(OrderSort.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: sort) { Haptics.tap() }
        .accessibilityLabel("Trier la liste par")
    }

    private var orderText: String {
        let s = store.data.settings
        var t = "*Commande — \(s.businessName)*\n"
        t += "\(Fmt.full.string(from: Date()))\n\n"
        for group in groups {
            if let name = group.name { t += "\n_\(name)_\n" }
            for l in group.lines {
                guard let p = store.product(l.productId) else { continue }
                var q = "\(Fmt.qty(l.quantity)) \(p.unitName)"
                if p.hasPack, l.quantity >= p.packSize {
                    q += " (\(Fmt.qty((l.quantity / p.packSize * 10).rounded() / 10)) \(p.packName))"
                }
                t += "• \(p.name) : \(q)\n"
            }
        }
        if !s.phone.isEmpty { t += "\nContact : \(s.phone)" }
        return t
    }
}

private struct OrderLineRow: View {
    @Environment(Store.self) private var store
    let line: OrderLine
    let product: Product
    let showSupplier: Bool
    let suppliers: [String]
    let onPickSupplier: (String) -> Void
    let onNewSupplier: () -> Void

    var body: some View {
        let stock = store.stockOf(product.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProductThumb(product: product, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink).lineLimit(1)
                    Text("Il me reste \(Fmt.qty(max(0, stock))) → \(Fmt.qty(max(0, stock) + line.quantity)) après")
                        .font(.caption).foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 6)
                Text(Fmt.money(line.lineCost))
                    .font(.money(15))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 10) {
                QuantityStepper(value: Binding(get: { line.quantity }, set: { v in
                    var l = line; l.quantity = v
                    store.updateOrderLine(l)
                }))
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    TextField("0", value: Binding(get: { line.unitCost }, set: { v in
                        var l = line; l.unitCost = max(0, v)
                        store.updateOrderLine(l)
                    }), format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.money(15))
                    .frame(maxWidth: 90)
                    Text("/ \(product.unitName)").font(.caption).foregroundStyle(Color.inkSecondary)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 40)
                .background(Color.chip, in: .capsule)
                .accessibilityLabel("Coût par \(product.unitName)")
            }
            supplierMenu
        }
        .padding(.vertical, 4)
    }

    private var supplierMenu: some View {
        Menu {
            ForEach(suppliers, id: \.self) { name in
                Button { onPickSupplier(name) } label: {
                    if name == line.supplierName { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Button { onNewSupplier() } label: { Label("Nouveau fournisseur…", systemImage: "plus") }
            if line.supplierName != nil {
                Button(role: .destructive) { onPickSupplier("") } label: { Label("Retirer le fournisseur", systemImage: "xmark") }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "building.2")
                Text(line.supplierName ?? "Choisir un fournisseur")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(line.supplierName == nil ? Color.inkSecondary : Color.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Color.chip, in: .capsule)
            .opacity(showSupplier || line.supplierName == nil ? 1 : 0.8)
        }
        .frame(minHeight: 44)
        .accessibilityLabel("Fournisseur : \(line.supplierName ?? "aucun")")
    }
}
