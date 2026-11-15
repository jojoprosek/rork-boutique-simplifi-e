import SwiftUI

struct ClientDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let clientId: UUID

    @State private var showPayment = false
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let client = store.client(clientId) {
                content(client)
            } else {
                EmptyStateView(icon: "person.slash", title: "Client introuvable", message: "Ce client a été supprimé.")
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func content(_ client: Client) -> some View {
        let owed = store.clientBalance(client.id)
        return ScrollView {
            VStack(spacing: 14) {
                header(client)
                debtCard(client, owed: owed)
                HStack(spacing: 10) {
                    Button("Encaisser un paiement") { showPayment = true }
                        .buttonStyle(BigButtonStyle(kind: .dark))
                        .disabled(owed <= 0)
                    Button("Relancer") { remind(client, owed: owed) }
                        .buttonStyle(BigButtonStyle(kind: .outline))
                        .frame(maxWidth: 150)
                        .disabled(owed <= 0)
                }
                stats(client)
                history(client)
            }
            .padding(16)
        }
        .navigationTitle(shortName(client))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showEdit = true } label: { Label("Modifier", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showPayment) { CollectDebtSheet(client: client) }
        .sheet(isPresented: $showEdit) { NavigationStack { ClientFormView(client: client) } }
        .confirmationDialog("Supprimer \(client.name) ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { store.deleteClient(client); dismiss() }
        } message: {
            Text("Son historique de ventes est conservé.")
        }
    }

    private func shortName(_ c: Client) -> String {
        let parts = c.name.split(separator: " ")
        return parts.count > 1 ? String(parts.last!) : c.name
    }

    // MARK: Header

    private func header(_ c: Client) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ClientAvatar(client: c, size: 84)
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.name).font(.title2.bold()).foregroundStyle(Color.ink)
                    Text(subtitle(c))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.gain)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.gainSoft, in: .capsule)
                }
            }
            HStack(spacing: 8) {
                contactButton("Appeler", icon: "phone") {
                    if let url = URL(string: "tel:\(c.phone.filter { $0.isNumber || $0 == "+" })") { openURL(url) }
                }
                .disabled(c.phone.isEmpty)
                contactButton("WhatsApp", icon: "message") {
                    if let url = ReceiptBuilder.whatsappURL(phone: c.whatsapp.isEmpty ? c.phone : c.whatsapp, text: "Bonjour \(c.name),") { openURL(url) }
                }
                ShareLink(item: statement(c)) {
                    contactLabel("Relevé", icon: "doc.text")
                }
            }
        }
        .card(radius: 26)
    }

    private func subtitle(_ c: Client) -> String {
        if c.address.isEmpty { return c.group.label }
        let place = c.address.components(separatedBy: ",").first ?? c.address
        return "\(c.group.label) · \(place)"
    }

    private func contactButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { contactLabel(title, icon: icon) }.buttonStyle(PressableStyle())
    }

    private func contactLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.gain)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.gainSoft, in: .capsule)
    }

    // MARK: Debt

    private func debtCard(_ c: Client, owed: Double) -> some View {
        let ratio = c.creditLimit > 0 ? min(1, owed / c.creditLimit) : 0
        return VStack(alignment: .leading, spacing: 10) {
            Text(owed > 0 ? "Me doit" : "Ne me doit rien").font(.headline).foregroundStyle(Color.ink)
            Text(Fmt.money(owed))
                .font(.money(40, weight: .heavy))
                .foregroundStyle(owed > 0 ? Color.loss : Color.gain)
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text("Limite \(Fmt.amount(c.creditLimit))").font(.subheadline).foregroundStyle(Color.inkSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.loss.opacity(0.12))
                    Capsule().fill(Color.loss).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 10)
            if let due = store.clientDueDate(c) {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: due)).day ?? 0
                Label(days >= 0 ? "Échéance dans \(days) jour\(days > 1 ? "s" : "")" : "En retard de \(-days) jour\(-days > 1 ? "s" : "")",
                      systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(days >= 0 ? Color.loss : Color.warn)
            }
        }
        .card(radius: 26, fill: owed > 0 ? .lossSoft : .gainSoft, padding: 22)
        .animation(.snappy, value: owed)
    }

    // MARK: Stats

    private func stats(_ c: Client) -> some View {
        let sales = store.data.sales.filter { $0.clientId == c.id && !$0.isCancelled }
        let month = Period.month.interval()
        let monthTotal = sales.filter { month.contains($0.date) }.reduce(0) { $0 + $1.total }
        var counts: [String: Double] = [:]
        for s in sales { for l in s.lines { counts[l.name, default: 0] += l.baseQuantity } }
        let fav = counts.max { $0.value < $1.value }?.key ?? "—"
        return HStack(spacing: 10) {
            statTile(icon: "banknote", title: "Acheté ce mois", value: Fmt.amount(monthTotal))
            statTile(icon: "cart", title: "Achats", value: "\(sales.count)")
            statTile(icon: "shippingbox", title: "Préféré", value: fav)
        }
    }

    private func statTile(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(Color.gain)
            Text(title).font(.caption).foregroundStyle(Color.inkSecondary).lineLimit(1)
            Text(value).font(.money(17)).foregroundStyle(Color.ink).lineLimit(2).minimumScaleFactor(0.7)
        }
        .card(radius: 20, padding: 12)
    }

    // MARK: History

    private struct Entry: Identifiable {
        let id: UUID
        let date: Date
        let title: String
        let amount: Double
        let icon: String
        let positive: Bool
        let sale: Sale?
    }

    private func entries(_ c: Client) -> [Entry] {
        var out: [Entry] = []
        for s in store.data.sales where s.clientId == c.id && !s.isCancelled {
            out.append(Entry(id: s.id, date: s.date, title: s.remaining > 0 ? "Achat à crédit" : "Achat",
                             amount: s.total, icon: "cart", positive: false, sale: s))
        }
        for p in store.data.debtPayments where p.clientId == c.id {
            let acc = store.account(p.accountId)
            out.append(Entry(id: p.id, date: p.date, title: "Paiement \(acc?.name.lowercased() ?? "")",
                             amount: p.amount, icon: acc?.kind.icon ?? "banknote", positive: true, sale: nil))
        }
        return out.sorted { $0.date > $1.date }
    }

    private func history(_ c: Client) -> some View {
        let list = entries(c)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Historique")
            VStack(spacing: 0) {
                if list.isEmpty {
                    EmptyStateView(icon: "clock", title: "Pas encore d'achat", message: "Les achats et paiements de ce client apparaîtront ici.")
                }
                ForEach(Array(list.prefix(30).enumerated()), id: \.element.id) { i, e in
                    let row = HStack(spacing: 12) {
                        IconBadge(systemName: e.icon, tint: e.positive ? .gain : .loss, fill: e.positive ? .gainSoft : .lossSoft, size: 38)
                        Text("\(Fmt.dayMonth.string(from: e.date)) · \(e.title)")
                            .font(.subheadline).foregroundStyle(Color.ink).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(Fmt.signed(e.positive ? e.amount : -e.amount))
                            .font(.money(16))
                            .foregroundStyle(e.positive ? Color.gain : Color.loss)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 58)
                    Group {
                        if let sale = e.sale {
                            NavigationLink { SaleDetailView(saleId: sale.id) } label: { row }
                                .buttonStyle(.plain)
                        } else {
                            row
                        }
                    }
                    if i < min(list.count, 30) - 1 { Divider().padding(.leading, 64) }
                }
            }
            .background(Color.card, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }

    // MARK: Actions

    private func remind(_ c: Client, owed: Double) {
        let s = store.data.settings
        let text = s.reminderTemplate
            .replacingOccurrences(of: "{nom}", with: c.name)
            .replacingOccurrences(of: "{montant}", with: Fmt.money(owed))
            .replacingOccurrences(of: "{boutique}", with: s.businessName)
        if let url = ReceiptBuilder.whatsappURL(phone: c.whatsapp.isEmpty ? c.phone : c.whatsapp, text: text) { openURL(url) }
    }

    private func statement(_ c: Client) -> String {
        var t = "Relevé de compte — \(c.name)\n\(store.data.settings.businessName)\n\n"
        for e in entries(c).reversed() {
            t += "\(Fmt.dayMonth.string(from: e.date)) · \(e.title) : \(Fmt.signed(e.positive ? e.amount : -e.amount))\n"
        }
        t += "\nReste à payer : \(Fmt.money(store.clientBalance(c.id)))"
        return t
    }
}

struct CollectDebtSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let client: Client
    @State private var amountText = ""
    @State private var accountId: UUID?

    var body: some View {
        let owed = store.clientBalance(client.id)
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Doit") { Text(Fmt.money(owed)).font(.money(18)).foregroundStyle(Color.loss) }
                }
                Section("Montant reçu") {
                    TextField("0", text: $amountText).keyboardType(.numberPad).font(.money(28))
                    HStack {
                        Button("Tout (\(Fmt.amount(owed)))") { amountText = Fmt.amount(owed) }
                        Spacer()
                        Button("Moitié") { amountText = Fmt.amount((owed / 2).rounded()) }
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
                }
                Section("Reçu sur") {
                    Picker("Compte", selection: Binding(get: { accountId ?? store.data.accounts.first?.id }, set: { accountId = $0 })) {
                        ForEach(store.data.accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if Fmt.parse(amountText) > 0 && Fmt.parse(amountText) < owed {
                    Section { Text("Il restera \(Fmt.money(owed - Fmt.parse(amountText))) à payer.").foregroundStyle(Color.inkSecondary) }
                }
            }
            .navigationTitle("Encaisser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        let amount = min(Fmt.parse(amountText), owed)
                        if let acc = store.account(accountId ?? store.data.accounts.first?.id ?? UUID()) {
                            store.recordDebtPayment(client: client, amount: amount, account: acc)
                        }
                        dismiss()
                    }
                    .disabled(Fmt.parse(amountText) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
