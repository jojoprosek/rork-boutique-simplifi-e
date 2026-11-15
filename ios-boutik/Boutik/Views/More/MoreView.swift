import SwiftUI

struct MoreView: View {
    @Environment(Store.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { ShopSettingsView() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "storefront.fill")
                                .font(.title2).foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.gain, in: .rect(cornerRadius: 16, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.data.settings.businessName).font(.headline)
                                Text("\(store.data.settings.businessType.label) · \(store.data.settings.currency)")
                                    .font(.subheadline).foregroundStyle(Color.inkSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Argent") {
                    link("Rapports", "chart.bar.fill", .gain) { ReportsView(initial: .month) }
                    link("Mes comptes", "wallet.bifold.fill", .gain) { AccountsView() }
                    link("Dépenses", "arrow.down.right", .loss) { ExpensesListView() }
                    link("Je dois", "building.2.fill", .loss) { PayablesView() }
                    link("On me doit", "person.badge.clock.fill", .warn) { DebtorsView() }
                }

                Section("Stock") {
                    link("Inventaire", "checklist", .ink) { InventoryView() }
                    link("Stock bas", "exclamationmark.triangle.fill", .warn) { LowStockView() }
                }

                Section("Réglages") {
                    link("Vente et crédit", "cart.fill", .ink) { SalesSettingsView() }
                    link("Sécurité", "lock.fill", .ink) { SecuritySettingsView() }
                    link("Affichage", "textformat.size", .ink) { DisplaySettingsView() }
                    link("Synchronisation", "arrow.triangle.2.circlepath", .ink) { SyncSettingsView() }
                    link("Abonnement", "star.fill", .gain) { SubscriptionView() }
                    link("Historique des actions", "clock.arrow.circlepath", .ink) { ActivityView() }
                }

                Section {
                    link("Aide sur WhatsApp", "questionmark.bubble.fill", .gain) { HelpView() }
                } footer: {
                    Text("Boutik · version 1.0").frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .navigationTitle("Plus")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { QuickActionsMenu() } }
        }
    }

    private func link<D: View>(_ title: String, _ icon: String, _ tint: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Color.chip, in: .rect(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(minHeight: 40)
    }
}

// MARK: - Settings screens

struct ShopSettingsView: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section("Boutique") {
                TextField("Nom", text: $store.data.settings.businessName)
                TextField("Propriétaire", text: $store.data.settings.ownerName)
                TextField("Téléphone", text: $store.data.settings.phone).keyboardType(.phonePad)
                TextField("E-mail", text: $store.data.settings.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Adresse", text: $store.data.settings.address)
                TextField("Secteur", text: $store.data.settings.sector)
                TextField("N° fiscal (facultatif)", text: $store.data.settings.taxNumber)
            }
            Section("Monnaie") {
                TextField("Monnaie", text: $store.data.settings.currency)
                Stepper("Décimales : \(store.data.settings.decimals)", value: $store.data.settings.decimals, in: 0...2)
            }
            Section("Type") {
                Picker("Je vends", selection: $store.data.settings.businessType) {
                    ForEach(BusinessType.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Reçu") {
                TextField("Message en bas du reçu", text: $store.data.settings.receiptFooter, axis: .vertical)
            }
        }
        .navigationTitle("Ma boutique")
        .toolbar(.hidden, for: .tabBar)
    }
}

struct SalesSettingsView: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Autoriser le crédit", isOn: $store.data.settings.allowCredit)
                Toggle("Client obligatoire", isOn: $store.data.settings.requireClient)
                Toggle("Vendre même sans stock", isOn: $store.data.settings.allowNegativeStock)
            }
            Section("Remises") {
                Stepper("Remise max : \(Int(store.data.settings.maxDiscountPercent)) %", value: $store.data.settings.maxDiscountPercent, in: 0...100, step: 5)
                Toggle("Note obligatoire pour une remise", isOn: $store.data.settings.noteRequiredForDiscount)
            }
            Section("Stock") {
                Stepper("Alerte par défaut : \(Fmt.qty(store.data.settings.defaultLowStock))", value: $store.data.settings.defaultLowStock, in: 0...500)
            }
            Section {
                TextField("Message", text: $store.data.settings.reminderTemplate, axis: .vertical)
            } header: { Text("Message de rappel") } footer: { Text("{nom}, {montant} et {boutique} sont remplacés automatiquement.") }
        }
        .navigationTitle("Vente et crédit")
        .toolbar(.hidden, for: .tabBar)
    }
}

struct SecuritySettingsView: View {
    @Environment(Store.self) private var store
    @State private var settingPin = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                if store.data.settings.pin == nil {
                    Button("Créer un code") { settingPin = true }
                } else {
                    Button("Changer le code") { settingPin = true }
                    Button("Supprimer le code", role: .destructive) {
                        store.data.settings.pin = nil
                        store.data.settings.useBiometrics = false
                    }
                }
            } footer: { Text("Le code est demandé à l'ouverture de l'app.") }
            if store.data.settings.pin != nil {
                Section {
                    Toggle("Face ID / Touch ID", isOn: $store.data.settings.useBiometrics)
                    Picker("Verrouiller après", selection: $store.data.settings.autoLockMinutes) {
                        Text("Immédiatement").tag(0)
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                    }
                }
            }
            Section {
                Label("Vos données sont chiffrées sur le téléphone.", systemImage: "lock.shield")
                    .font(.subheadline).foregroundStyle(Color.inkSecondary)
            }
        }
        .navigationTitle("Sécurité")
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $settingPin) { SetPinSheet() }
    }
}

struct DisplaySettingsView: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Mode", selection: $store.data.settings.mode) {
                    ForEach(AppMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: { Text("Mode") } footer: { Text("Simple : l'essentiel. Complet : références, paliers de prix et plus de détails.") }
            Section("Apparence") {
                Picker("Thème", selection: $store.data.settings.theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Grands caractères", isOn: $store.data.settings.largeText)
            }
            Section("Langue") {
                LabeledContent("Langue", value: "Français")
            }
        }
        .navigationTitle("Affichage")
        .toolbar(.hidden, for: .tabBar)
    }
}

struct SyncSettingsView: View {
    @Environment(Store.self) private var store
    @Environment(SyncEngine.self) private var sync
    @State private var confirmDemo = false
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                LabeledContent("Connexion", value: sync.isOnline ? "En ligne" : "Hors ligne")
                LabeledContent("En attente d'envoi", value: "\(store.data.pending.count)")
                LabeledContent("Dernière synchro", value: store.data.lastSync.map { Fmt.full.string(from: $0) } ?? "Jamais")
                Toggle("Seulement en Wi‑Fi", isOn: $store.data.settings.syncWifiOnly)
                Button("Synchroniser maintenant") { Task { await sync.syncIfPossible() } }
                    .disabled(!sync.isOnline || sync.isSyncing)
            } footer: { Text("Tout est enregistré sur le téléphone d'abord. Les changements partent dès que le réseau revient.") }

            Section("Données") {
                ShareLink(item: CSVExport.products(store: store), preview: SharePreview("Produits.csv")) {
                    Label("Exporter les produits", systemImage: "square.and.arrow.up")
                }
                Button("Recharger la boutique exemple") { confirmDemo = true }
                Button("Tout effacer", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Synchronisation")
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog("Remplacer vos données par la boutique exemple ?", isPresented: $confirmDemo, titleVisibility: .visible) {
            Button("Remplacer", role: .destructive) { store.loadDemo() }
        }
        .confirmationDialog("Effacer toutes les ventes, produits et clients ?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Tout effacer", role: .destructive) { store.startEmpty(keeping: store.data.settings) }
        }
    }
}

struct ExpensesListView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let list = store.data.expenses.sorted { $0.date > $1.date }
        List {
            if list.isEmpty {
                EmptyStateView(icon: "arrow.down.right", title: "Aucune dépense", message: "Notez le transport, le loyer, l'électricité…")
                    .listRowBackground(Color.clear)
            }
            ForEach(list) { e in
                HStack(spacing: 12) {
                    IconBadge(systemName: "arrow.down.right", tint: .loss, fill: .lossSoft, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.category).font(.subheadline.weight(.semibold))
                        Text("\(Fmt.shortDate(e.date))\(e.note.isEmpty ? "" : " · \(e.note)") · \(store.account(e.accountId)?.name ?? "")")
                            .font(.caption).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    }
                    Spacer()
                    Text("−" + Fmt.money(e.amount)).font(.money(15)).foregroundStyle(Color.loss)
                }
                .frame(minHeight: 50)
                .swipeActions { Button("Supprimer", role: .destructive) { store.deleteExpense(e) } }
            }
        }
        .navigationTitle("Dépenses")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { router.sheet = .expense } label: { Image(systemName: "plus") } }
        }
    }
}

struct ActivityView: View {
    @Environment(Store.self) private var store
    var body: some View {
        List(store.data.activity) { a in
            VStack(alignment: .leading, spacing: 2) {
                Text(a.text).font(.subheadline)
                Text(Fmt.full.string(from: a.date)).font(.caption).foregroundStyle(Color.inkSecondary)
            }
        }
        .overlay {
            if store.data.activity.isEmpty {
                EmptyStateView(icon: "clock", title: "Rien pour l'instant", message: "Chaque action sera notée ici.")
            }
        }
        .navigationTitle("Historique")
        .toolbar(.hidden, for: .tabBar)
    }
}

struct HelpView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section("Questions fréquentes") {
                DisclosureGroup("Comment savoir ce qu'il me reste ?") {
                    Text("« Il me reste » = ce que vous avez vendu moins ce que les produits vous ont coûté et vos dépenses.").font(.subheadline)
                }
                DisclosureGroup("Ça marche sans internet ?") {
                    Text("Oui. Tout est gardé sur le téléphone et envoyé quand le réseau revient.").font(.subheadline)
                }
                DisclosureGroup("Je me suis trompé, comment annuler ?") {
                    Text("Touchez « Annuler » juste après l'action, ou ouvrez la vente et choisissez « Annuler cette vente ».").font(.subheadline)
                }
            }
            Section {
                Button {
                    if let url = ReceiptBuilder.whatsappURL(phone: nil, text: "Bonjour, j'ai une question sur Boutik.") { openURL(url) }
                } label: { Label("Écrire au support sur WhatsApp", systemImage: "message.fill") }
            }
        }
        .navigationTitle("Aide")
        .toolbar(.hidden, for: .tabBar)
    }
}
