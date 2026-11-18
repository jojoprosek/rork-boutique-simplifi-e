import SwiftUI

struct HomeView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @State private var period: Period = .today

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    topControls
                    if store.data.sales.isEmpty { FirstSaleGuide() }
                    heroCard
                    debtCards
                    accountsRow
                    if store.data.settings.stockAlertOnHome ?? true { LowStockCard() }
                    alerts
                    if !favorites.isEmpty { favoritesRow }
                    recentOperations
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle(store.data.settings.businessName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { QuickActionsMenu() }
            }
        }
    }

    // MARK: Header controls

    private var topControls: some View {
        VStack(alignment: .leading, spacing: 0) {
        SyncCapsule()
        HStack(spacing: 8) {
            Picker("Période", selection: $period) {
                ForEach(Period.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Button {
                withAnimation(.snappy) { store.hideAmounts.toggle() }
                Haptics.tap()
            } label: {
                Image(systemName: store.hideAmounts ? "eye.slash" : "eye")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 36)
                    .background(Color.card, in: .capsule)
            }
            .accessibilityLabel(store.hideAmounts ? "Afficher les montants" : "Masquer les montants")
        }
        }
    }

    // MARK: Hero

    private var current: Store.Stats { store.stats(period.interval()) }
    private var previous: Store.Stats { store.stats(period.interval(offset: -1)) }

    private func hidden(_ s: String) -> String { store.hideAmounts ? "••••••" : s }

    private var heroCard: some View {
        let cur = current
        let prev = previous
        let delta: Double? = prev.left != 0 ? (cur.left - prev.left) / abs(prev.left) * 100 : nil
        return NavigationLink {
            ReportsView(initial: period)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Il me reste").font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
                    Spacer()
                    if let delta, !store.hideAmounts {
                        Text("\(delta >= 0 ? "+" : "−")\(Int(abs(delta).rounded())) % vs \(period.previousLabel)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(delta >= 0 ? Color.gain : Color.loss)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(delta >= 0 ? Color.gainSoft : Color.lossSoft, in: .capsule)
                    }
                }
                Text(hidden(Fmt.money(cur.left)))
                    .font(.money(44, weight: .heavy))
                    .foregroundStyle(cur.left >= 0 ? Color.gain : Color.loss)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                HStack(spacing: 0) {
                    statColumn(icon: "chart.line.uptrend.xyaxis", title: "Vendu", value: cur.sold, color: .gain)
                    Rectangle().fill(Color.hairline).frame(width: 1, height: 44).padding(.horizontal, 12)
                    statColumn(icon: "chart.line.downtrend.xyaxis", title: "Dépensé", value: cur.spent, color: .loss)
                }
            }
            .card(radius: 28, padding: 22)
        }
        .buttonStyle(PressableStyle())
        .animation(.snappy, value: period)
    }

    private func statColumn(icon: String, title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(Color.inkSecondary)
                Text(hidden(Fmt.amount(value))).font(.money(22)).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Debts

    private var debtCards: some View {
        HStack(spacing: 12) {
            NavigationLink { DebtorsView() } label: {
                debtCard(icon: "person.2", title: "On me doit", value: store.totalOwedToMe, color: .gain, fill: .gainSoft)
            }
            NavigationLink { PayablesView() } label: {
                debtCard(icon: "arrow.left.arrow.right", title: "Je dois", value: store.totalIOwe, color: .loss, fill: .lossSoft)
            }
        }
        .buttonStyle(PressableStyle())
    }

    private func debtCard(icon: String, title: String, value: Double, color: Color, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(color).font(.body.weight(.semibold))
                Text(title).font(.headline).foregroundStyle(Color.ink)
            }
            Text(hidden(Fmt.money(value)))
                .font(.money(22, weight: .heavy))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .card(radius: 24, fill: fill, padding: 16)
    }

    // MARK: Accounts

    private var accountsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(store.data.accounts) { acc in
                    NavigationLink { AccountsView() } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: acc.kind.icon).font(.title3).foregroundStyle(Color.gain)
                            Text(acc.name).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(1)
                            Text(hidden(Fmt.amount(store.balance(of: acc))))
                                .font(.money(20)).foregroundStyle(Color.ink)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(width: 140, alignment: .leading)
                        .card(radius: 22, padding: 14)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: Alerts

    @ViewBuilder
    private var alerts: some View {
        let late = store.data.clients.filter { store.isOverdue($0) }
        VStack(spacing: 10) {
            if !late.isEmpty {
                NavigationLink { DebtorsView() } label: {
                    AlertRow(icon: "clock.badge.exclamationmark",
                             title: late.count == 1 ? "1 client en retard de paiement" : "\(late.count) clients en retard de paiement",
                             subtitle: late.prefix(3).map(\.name).joined(separator: ", "),
                             tint: .warn, fill: .warnSoft)
                }
            }
            if store.data.settings.plan == nil && store.trialDaysLeft <= 5 {
                NavigationLink { SubscriptionView() } label: {
                    AlertRow(icon: "sparkles",
                             title: "Essai gratuit : \(store.trialDaysLeft) jour\(store.trialDaysLeft > 1 ? "s" : "") restant\(store.trialDaysLeft > 1 ? "s" : "")",
                             subtitle: "Choisissez un plan pour continuer à vendre",
                             tint: .ink, fill: .card)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Favorites

    private var favorites: [Product] { store.activeProducts.filter(\.isFavorite) }

    private var favoritesRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Produits favoris", action: "Vendre") { router.tab = .sell }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(favorites) { p in
                        HStack(spacing: 10) {
                            ProductThumb(product: p, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink).lineLimit(1)
                                Text("Reste \(Fmt.qty(store.stockOf(p.id)))").font(.caption).foregroundStyle(Color.inkSecondary)
                            }
                        }
                        .padding(10)
                        .background(Color.card, in: .rect(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    // MARK: Recent

    private struct Operation: Identifiable {
        let id: UUID
        let date: Date
        let title: String
        let amount: Double
    }

    private var operations: [Operation] {
        var ops: [Operation] = []
        for s in store.data.sales.suffix(12) where !s.isCancelled {
            let credit = s.remaining > 0 ? " (crédit)" : ""
            ops.append(Operation(id: s.id, date: s.date, title: "Vente · \(s.clientName)\(credit)", amount: s.total))
        }
        for e in store.data.expenses.suffix(8) {
            ops.append(Operation(id: e.id, date: e.date, title: "Dépense · \(e.category)", amount: -e.amount))
        }
        for p in store.data.debtPayments.suffix(6) {
            let name = store.client(p.clientId)?.name ?? "Client"
            ops.append(Operation(id: p.id, date: p.date, title: "Paiement · \(name)", amount: p.amount))
        }
        for i in store.data.incomes.suffix(4) {
            ops.append(Operation(id: i.id, date: i.date, title: "Entrée · \(i.label)", amount: i.amount))
        }
        return Array(ops.sorted { $0.date > $1.date }.prefix(5))
    }

    private var recentOperations: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Dernières opérations")
            VStack(spacing: 0) {
                if operations.isEmpty {
                    EmptyStateView(icon: "tray", title: "Rien pour l'instant", message: "Vos ventes et dépenses apparaîtront ici.")
                }
                ForEach(Array(operations.enumerated()), id: \.element.id) { i, op in
                    HStack(spacing: 12) {
                        Text(Fmt.shortDate(op.date))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: 52, alignment: .leading)
                        Rectangle().fill(Color.hairline).frame(width: 1, height: 22)
                        Text(op.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(hidden(Fmt.signed(op.amount)))
                            .font(.money(16))
                            .foregroundStyle(op.amount >= 0 ? Color.gain : Color.loss)
                    }
                    .frame(minHeight: 50)
                    .padding(.horizontal, 16)
                    if i < operations.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .background(Color.card, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }
}

// MARK: - Low stock alert

/// Home card listing the products whose stock is at or under the alert threshold.
struct LowStockCard: View {
    @Environment(Store.self) private var store
    @State private var showThreshold = false
    @State private var showOrder = false

    private let maxRows = 5

    var body: some View {
        let low = store.lowStockProducts
        let global = store.data.settings.stockAlertThreshold
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconBadge(systemName: low.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                          tint: low.isEmpty ? .gain : .loss,
                          fill: low.isEmpty ? .gainSoft : .lossSoft, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(low.isEmpty ? "Stock en ordre" : (low.count == 1 ? "1 produit presque fini" : "\(low.count) produits presque finis"))
                        .font(.headline).foregroundStyle(Color.ink)
                        .contentTransition(.numericText())
                    Text(global.map { "Alerte à \(Fmt.qty($0)) ou moins" } ?? "Alerte selon le seuil de chaque produit")
                        .font(.caption).foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 8)
                Button { showThreshold = true } label: {
                    Label("Seuil", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Color.chip, in: .capsule)
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Régler le seuil d'alerte")
            }
            .padding(16)

            if !low.isEmpty {
                ForEach(low.prefix(maxRows)) { p in
                    Divider().padding(.leading, 16)
                    HStack(spacing: 0) {
                        NavigationLink { ProductDetailView(productId: p.id) } label: { row(p) }
                            .buttonStyle(.plain)
                        Button {
                            store.addToOrder(p)
                            showOrder = true
                        } label: {
                            Text("Commander")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.darkButtonText)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 34)
                                .background(Color.darkButton, in: .capsule)
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(PressableStyle())
                        .padding(.trailing, 16)
                        .accessibilityLabel("Commander \(p.name)")
                    }
                }
                if !store.orderLines.isEmpty {
                    Divider().padding(.leading, 16)
                    Button { showOrder = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "list.clipboard.fill")
                            Text("Ma liste de commande").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(store.orderLines.count)")
                                .font(.money(15))
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(Color.warnSoft, in: .capsule)
                                .contentTransition(.numericText())
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                        }
                        .foregroundStyle(Color.warn)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if low.count > maxRows {
                    Divider().padding(.leading, 16)
                    NavigationLink { LowStockView() } label: {
                        HStack {
                            Text("Voir les \(low.count) produits").font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                        }
                        .foregroundStyle(Color.gain)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.card, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
        .animation(.snappy, value: low.map(\.id))
        .sheet(isPresented: $showThreshold) { StockThresholdSheet() }
        .sheet(isPresented: $showOrder) { OrderListSheet() }
    }

    private func row(_ p: Product) -> some View {
        let qty = store.stockOf(p.id)
        let threshold = store.alertThreshold(for: p)
        let out = qty <= 0
        return HStack(spacing: 12) {
            ProductThumb(product: p, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink).lineLimit(1)
                // Fill bar: how much is left compared with the threshold.
                GeometryReader { geo in
                    Capsule().fill(Color.chip)
                        .overlay(alignment: .leading) {
                            Capsule().fill(out ? Color.loss : Color.warn)
                                .frame(width: geo.size.width * min(1, max(0.04, threshold > 0 ? qty / threshold : 0)))
                        }
                }
                .frame(height: 5)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(out ? "Épuisé" : Fmt.qty(qty))
                    .font(.money(17))
                    .foregroundStyle(out ? Color.loss : Color.ink)
                Text("seuil \(Fmt.qty(threshold))").font(.caption2).foregroundStyle(Color.inkSecondary)
            }
            .padding(.trailing, 10)
        }
        .padding(.leading, 16)
        .frame(minHeight: 60)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.name), il reste \(Fmt.qty(qty)), seuil \(Fmt.qty(threshold))")
    }
}

/// Lets the shopkeeper choose the threshold used by the home alert.
struct StockThresholdSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var useGlobal = false
    @State private var value: Double = 10
    @State private var showOnHome = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Seuil", selection: $useGlobal) {
                        Text("Par produit").tag(false)
                        Text("Le même pour tous").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if useGlobal {
                    Section {
                        HStack(spacing: 16) {
                            Button { value = max(0, value - 1); Haptics.tap() } label: {
                                Image(systemName: "minus").font(.title3.weight(.bold)).frame(width: 52, height: 52)
                                    .background(Color.chip, in: .circle)
                            }
                            .buttonStyle(.plain)
                            VStack(spacing: 0) {
                                TextField("0", value: $value, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .font(.money(40, weight: .heavy))
                                Text("ou moins").font(.footnote).foregroundStyle(Color.inkSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            Button { value += 1; Haptics.tap() } label: {
                                Image(systemName: "plus").font(.title3.weight(.bold)).frame(width: 52, height: 52)
                                    .background(Color.chip, in: .circle)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        HStack {
                            ForEach([5.0, 10, 20, 50], id: \.self) { v in
                                Button(Fmt.qty(v)) { value = v; Haptics.tap() }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(value == v ? Color.darkButtonText : Color.ink)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(value == v ? Color.darkButton : Color.chip, in: .capsule)
                                    .buttonStyle(.plain)
                            }
                        }
                    } footer: {
                        Text("\(preview) produit\(preview > 1 ? "s" : "") seront signalés.")
                    }
                } else {
                    Section {
                        Text("Chaque produit utilise son propre seuil, réglable dans sa fiche (Modifier → Stock).")
                            .font(.subheadline).foregroundStyle(Color.inkSecondary)
                    }
                }
                Section {
                    Toggle("Afficher sur l'accueil", isOn: $showOnHome)
                } footer: {
                    Text("Vous pourrez le réactiver dans Plus → Vente et crédit.")
                }
            }
            .navigationTitle("Alerte de stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        store.data.settings.stockAlertThreshold = useGlobal ? max(0, value) : nil
                        store.data.settings.stockAlertOnHome = showOnHome
                        Haptics.success()
                        dismiss()
                    }
                }
            }
            .onAppear {
                let s = store.data.settings
                useGlobal = s.stockAlertThreshold != nil
                value = s.stockAlertThreshold ?? s.defaultLowStock
                showOnHome = s.stockAlertOnHome ?? true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var preview: Int {
        store.activeProducts.filter { store.stockOf($0.id) <= max(0, value) }.count
    }
}

struct AlertRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let fill: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Color.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Color.inkSecondary)
        }
        .card(radius: 24, fill: fill, padding: 16)
    }
}

struct SyncCapsule: View {
    @Environment(Store.self) private var store
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        let pending = store.data.pending.count
        let (icon, text, tint, fill): (String, String, Color, Color) = {
            if sync.isSyncing { return ("arrow.triangle.2.circlepath", "Envoi en cours…", .ink, .chip) }
            if pending == 0 { return ("checkmark.icloud", "Tout est à jour", .gain, .gainSoft) }
            if !sync.isOnline { return ("icloud.slash", "Hors ligne · \(pending) opération\(pending > 1 ? "s" : "") à envoyer", .warn, .warnSoft) }
            return ("icloud.and.arrow.up", "\(pending) opération\(pending > 1 ? "s" : "") à envoyer", .warn, .warnSoft)
        }()
        HStack(spacing: 6) {
            Image(systemName: icon)
                .symbolEffect(.rotate, isActive: sync.isSyncing)
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(fill, in: .capsule)
        .padding(.bottom, 8)
        .animation(.snappy, value: pending)
        .accessibilityElement(children: .combine)
    }
}

struct FirstSaleGuide: View {
    @Environment(Router.self) private var router
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconBadge(systemName: "hand.tap", tint: .white, fill: .gain, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Faites votre première vente").font(.headline).foregroundStyle(Color.ink)
                    Text("Touchez un produit, puis Payer. C'est tout.").font(.subheadline).foregroundStyle(Color.inkSecondary)
                }
            }
            Button("Commencer") { router.tab = .sell }
                .buttonStyle(BigButtonStyle(kind: .dark))
        }
        .card(radius: 26, fill: .gainSoft)
    }
}
