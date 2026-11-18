import SwiftUI

/// Supplier order list, pre-filled with what is missing to get back to the alert threshold.
struct OrderListSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var onCredit = false
    @State private var accountId: UUID?
    @State private var supplier = ""
    @State private var confirmClear = false

    private var lines: [OrderLine] { store.orderLines }
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
                    Section { totalHeader }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                    Section {
                        ForEach(lines) { line in
                            if let p = store.product(line.productId) {
                                OrderLineRow(line: line, product: p)
                            }
                        }
                        .onDelete { idx in
                            store.removeFromOrder(idx.map { lines[$0].id })
                        }
                    } header: {
                        Text("À commander")
                    } footer: {
                        Text("Quantités calculées pour revenir au seuil d'alerte. Glissez une ligne vers la gauche pour la retirer.")
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

    private var orderText: String {
        let s = store.data.settings
        var t = "*Commande — \(s.businessName)*\n"
        t += "\(Fmt.full.string(from: Date()))\n\n"
        for l in lines {
            guard let p = store.product(l.productId) else { continue }
            var q = "\(Fmt.qty(l.quantity)) \(p.unitName)"
            if p.hasPack, l.quantity >= p.packSize {
                q += " (\(Fmt.qty((l.quantity / p.packSize * 10).rounded() / 10)) \(p.packName))"
            }
            t += "• \(p.name) : \(q)\n"
        }
        if !s.phone.isEmpty { t += "\nContact : \(s.phone)" }
        return t
    }
}

private struct OrderLineRow: View {
    @Environment(Store.self) private var store
    let line: OrderLine
    let product: Product

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
                Text(Fmt.money(line.quantity * line.unitCost))
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
        }
        .padding(.vertical, 4)
    }
}
