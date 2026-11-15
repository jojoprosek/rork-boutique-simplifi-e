import SwiftUI

struct AccountsView: View {
    @Environment(Store.self) private var store
    @State private var showTransfer = false
    @State private var editing: MoneyAccount?
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tout mon argent").font(.subheadline.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                    Text(Fmt.money(store.totalCash)).font(.money(36, weight: .heavy)).foregroundStyle(Color.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .card(radius: 28)

                ForEach(store.data.accounts) { a in
                    Button { editing = a } label: {
                        HStack(spacing: 14) {
                            IconBadge(systemName: a.kind.icon, size: 46)
                            Text(a.name).font(.headline).foregroundStyle(Color.ink)
                            Spacer()
                            Text(Fmt.money(store.balance(of: a))).font(.money(18)).foregroundStyle(Color.ink)
                        }
                        .card(radius: 22, padding: 16)
                    }
                    .buttonStyle(PressableStyle())
                }

                HStack(spacing: 10) {
                    Button { showTransfer = true } label: { Label("Transfert", systemImage: "arrow.left.arrow.right") }
                        .buttonStyle(BigButtonStyle(kind: .dark))
                    Button { adding = true } label: { Label("Compte", systemImage: "plus") }
                        .buttonStyle(BigButtonStyle(kind: .outline))
                }

                if !recent.isEmpty {
                    SectionHeader(title: "Derniers transferts").padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(recent) { t in
                            HStack {
                                Text("\(store.account(t.fromId)?.name ?? "?") → \(store.account(t.toId)?.name ?? "?")")
                                    .font(.subheadline)
                                Spacer()
                                Text(Fmt.money(t.amount)).font(.money(15))
                            }
                            .padding(.horizontal, 16).frame(minHeight: 50)
                        }
                    }
                    .background(Color.card, in: .rect(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle("Mes comptes")
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showTransfer) { TransferFormView() }
        .sheet(item: $editing) { a in AccountFormView(account: a) }
        .sheet(isPresented: $adding) { AccountFormView(account: nil) }
    }

    private var recent: [Transfer] { Array(store.data.transfers.sorted { $0.date > $1.date }.prefix(8)) }
}

struct AccountFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let account: MoneyAccount?
    @State private var draft = MoneyAccount(name: "", kind: .mobile, openingBalance: 0)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex. Wave, MTN MoMo)", text: $draft.name)
                Picker("Type", selection: $draft.kind) {
                    Text("Espèces").tag(AccountKind.cash)
                    Text("Mobile money").tag(AccountKind.mobile)
                    Text("Banque").tag(AccountKind.bank)
                    Text("Autre").tag(AccountKind.other)
                }
                LabeledContent("Solde de départ") {
                    TextField("0", value: $draft.openingBalance, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle(account == nil ? "Nouveau compte" : "Compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { store.saveAccount(draft); dismiss() }
                        .disabled(draft.name.isEmpty)
                }
            }
            .onAppear { if let account { draft = account } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Je dois

struct PayablesView: View {
    @Environment(Store.self) private var store
    @State private var adding = false
    @State private var paying: Payable?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Je dois au total").font(.subheadline.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                    Text(Fmt.money(store.totalIOwe)).font(.money(32, weight: .heavy)).foregroundStyle(Color.loss)
                }
                .padding(.vertical, 6)
            }
            let open = store.data.payables.filter { $0.remaining > 0 }.sorted { $0.dueDate < $1.dueDate }
            if open.isEmpty {
                EmptyStateView(icon: "checkmark.seal", title: "Vous ne devez rien", message: "Ajoutez un fournisseur ou un prêt à rembourser.")
                    .listRowBackground(Color.clear)
            } else {
                Section("À payer") {
                    ForEach(open) { p in
                        Button { paying = p } label: { row(p) }.buttonStyle(.plain)
                    }
                }
            }
            let done = store.data.payables.filter { $0.remaining == 0 }
            if !done.isEmpty {
                Section("Réglé") { ForEach(done) { row($0).opacity(0.55) } }
            }
        }
        .navigationTitle("Je dois")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $adding) { PayableFormView() }
        .sheet(item: $paying) { PayPayableSheet(payable: $0) }
    }

    private func row(_ p: Payable) -> some View {
        let late = p.dueDate < Date() && p.remaining > 0
        return HStack(spacing: 12) {
            IconBadge(systemName: "building.2", tint: .loss, fill: .lossSoft, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.creditor).font(.headline)
                Text(p.remaining == 0 ? "Payé" : (late ? "En retard · " : "Avant le ") + Fmt.dayMonth.string(from: p.dueDate))
                    .font(.caption).foregroundStyle(late ? Color.loss : Color.inkSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(p.remaining)).font(.money(16)).foregroundStyle(Color.ink)
                if p.paid > 0 && p.remaining > 0 { Text("sur \(Fmt.amount(p.amount))").font(.caption).foregroundStyle(Color.inkSecondary) }
            }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
    }
}

struct PayableFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creditor = ""
    @State private var amount = ""
    @State private var due = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { AmountField(text: $amount, color: .loss) }.listRowBackground(Color.clear)
                Section {
                    TextField("À qui ? (fournisseur, personne…)", text: $creditor)
                    DatePicker("À payer avant", selection: $due, displayedComponents: .date)
                    TextField("Note", text: $note)
                }
            }
            .navigationTitle("Je dois")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.addPayable(Payable(creditor: creditor, amount: Fmt.parse(amount), dueDate: due, note: note))
                        dismiss()
                    }
                    .disabled(creditor.isEmpty || Fmt.parse(amount) <= 0)
                }
            }
        }
    }
}

struct PayPayableSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let payable: Payable
    @State private var amount = ""
    @State private var accountId: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section { AmountField(text: $amount) }.listRowBackground(Color.clear)
                Section {
                    LabeledContent("Reste à payer", value: Fmt.money(payable.remaining))
                    Button("Tout payer") { amount = Fmt.amount(payable.remaining) }
                    AccountPicker(selection: $accountId)
                }
            }
            .navigationTitle("Payer \(payable.creditor)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Payer") {
                        guard let id = accountId ?? store.data.accounts.first?.id, let acc = store.account(id) else { return }
                        store.payPayable(payable, amount: min(Fmt.parse(amount), payable.remaining), account: acc)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(Fmt.parse(amount) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
