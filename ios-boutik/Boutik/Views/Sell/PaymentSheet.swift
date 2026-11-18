import SwiftUI

enum ReceiptChoice: String, CaseIterable, Identifiable {
    case print, whatsapp, pdf, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .print: "Imprimer"
        case .whatsapp: "WhatsApp"
        case .pdf: "PDF"
        case .none: "Aucun"
        }
    }
    var icon: String {
        switch self {
        case .print: "printer"
        case .whatsapp: "message"
        case .pdf: "doc.richtext"
        case .none: "nosign"
        }
    }
}

struct PaymentSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var cart: CartModel

    @State private var method: PaymentMethod = .cash
    @State private var receivedText = ""
    @State private var secondText = ""
    @State private var accountId: UUID?
    @State private var receipt: ReceiptChoice = .none
    @State private var showClientPicker = false
    @State private var limitAlert = false
    @State private var errorText: String?
    @State private var completed: Sale?
    @State private var changeGiven: Double = 0
    @FocusState private var amountFocused: Bool

    private var total: Double { cart.total(store: store) }
    private var client: Client? { store.client(cart.clientId) }
    private var received: Double { Fmt.parse(receivedText) }
    private var second: Double { Fmt.parse(secondText) }

    var body: some View {
        NavigationStack {
            Group {
                if let completed {
                    SaleSuccessView(sale: completed, change: changeGiven, receipt: receipt) {
                        cart.clear()
                        dismiss()
                    }
                } else {
                    form
                }
            }
            .background(Color.canvas.ignoresSafeArea())
            .toolbar {
                if completed == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Retour") { dismiss() } }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(completed != nil)
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("À payer").font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
                    Text(Fmt.money(total))
                        .font(.money(46, weight: .heavy))
                        .foregroundStyle(Color.gain)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }

                clientRow
                methodGrid
                methodDetail
                receiptPicker

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.loss)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button("Valider la vente") { validate(override: false) }
                .buttonStyle(BigButtonStyle(kind: .green))
                .accessibilityIdentifier("payment.validate")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.canvas.opacity(0.95))
        }
        .sheet(isPresented: $showClientPicker) { ClientPickerView(selected: $cart.clientId) }
        .alert("Limite de crédit dépassée", isPresented: $limitAlert) {
            Button("Annuler", role: .cancel) {}
            Button("Autoriser (gérant)") { validate(override: true) }
        } message: {
            if let client {
                Text("\(client.name) doit déjà \(Fmt.money(store.clientBalance(client.id))). Sa limite est de \(Fmt.money(client.creditLimit)).")
            }
        }
        .onAppear { receivedText = Fmt.amount(total) }
        .onChange(of: method) { _, m in
            errorText = nil
            accountId = m.accountKind.flatMap { store.defaultAccount(for: $0)?.id }
            switch m {
            case .cash: receivedText = Fmt.amount(total)
            case .credit: receivedText = ""
            case .mixed: receivedText = ""; secondText = ""
            default: break
            }
        }
    }

    private var clientRow: some View {
        HStack(spacing: 12) {
            ClientAvatar(client: client, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(client?.name ?? "Client de passage").font(.headline).foregroundStyle(Color.ink)
                if let client {
                    let owed = store.clientBalance(client.id)
                    Text(owed > 0 ? "Doit déjà \(Fmt.money(owed))" : client.group.label)
                        .font(.caption).foregroundStyle(owed > 0 ? Color.loss : Color.inkSecondary)
                }
            }
            Spacer()
            Button("Changer") { showClientPicker = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.gain)
                .padding(.horizontal, 16).frame(height: 40)
                .background(Color.chip, in: .capsule)
        }
    }

    private var methodGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(PaymentMethod.allCases) { m in
                let selected = method == m
                Button {
                    withAnimation(.snappy) { method = m }
                    Haptics.tap()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: m.icon).font(.title2)
                        Text(m.label).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Color.gain : Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(selected ? Color.gainSoft : Color.card, in: .rect(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(selected ? Color.gain : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var methodDetail: some View {
        switch method {
        case .cash:
            VStack(alignment: .leading, spacing: 12) {
                Text("Reçu").font(.headline)
                HStack(spacing: 8) {
                    amountField($receivedText)
                    ForEach(quickAmounts, id: \.self) { a in
                        Button(Fmt.amount(a)) { receivedText = Fmt.amount(a); Haptics.tap() }
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 12).frame(height: 44)
                            .background(Color.chip, in: .capsule)
                    }
                }
                if received >= total {
                    resultBox(title: "Monnaie à rendre", value: received - total, color: .gain, fill: .gainSoft)
                } else if received > 0 {
                    resultBox(title: "Reste à payer (à crédit)", value: total - received, color: .loss, fill: .lossSoft)
                }
            }
            .card(radius: 24)
        case .mobile, .card, .transfer:
            VStack(alignment: .leading, spacing: 10) {
                Text("Compte qui reçoit l'argent").font(.headline)
                accountPicker(kind: method.accountKind)
            }
            .card(radius: 24)
        case .credit:
            VStack(alignment: .leading, spacing: 12) {
                Text("Payé maintenant (facultatif)").font(.headline)
                amountField($receivedText)
                resultBox(title: "Mis sur son compte", value: max(0, total - received), color: .loss, fill: .lossSoft)
                if client == nil {
                    Label("Choisissez un client pour vendre à crédit.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.subheadline).foregroundStyle(Color.warn)
                }
            }
            .card(radius: 24)
        case .mixed:
            VStack(alignment: .leading, spacing: 12) {
                Text("Espèces").font(.headline)
                amountField($receivedText)
                Text("Mobile money").font(.headline)
                amountField($secondText)
                let rest = total - received - second
                if rest > 0 {
                    resultBox(title: "Reste (à crédit)", value: rest, color: .loss, fill: .lossSoft)
                } else {
                    resultBox(title: "Monnaie à rendre", value: -rest, color: .gain, fill: .gainSoft)
                }
            }
            .card(radius: 24)
        }
    }

    private func amountField(_ text: Binding<String>) -> some View {
        TextField("0", text: text)
            .keyboardType(.numberPad)
            .font(.money(26))
            .focused($amountFocused)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.canvas, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
    }

    private func resultBox(title: String, value: Double, color: Color, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(Fmt.money(value)).font(.money(28, weight: .heavy)).foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(fill, in: .rect(cornerRadius: 16, style: .continuous))
        .animation(.snappy, value: value)
    }

    private func accountPicker(kind: AccountKind?) -> some View {
        let accounts = store.data.accounts.filter { kind == nil || $0.kind == kind }
        let list = accounts.isEmpty ? store.data.accounts : accounts
        return Picker("Compte", selection: Binding(get: { accountId ?? list.first?.id }, set: { accountId = $0 })) {
            ForEach(list) { Text($0.name).tag(Optional($0.id)) }
        }
        .pickerStyle(.segmented)
    }

    private var quickAmounts: [Double] {
        guard total > 0 else { return [] }
        var out: [Double] = []
        for step in [1_000.0, 5_000, 10_000] {
            let v = (total / step).rounded(.up) * step
            if v > total && !out.contains(v) { out.append(v) }
        }
        return Array(out.prefix(2))
    }

    private var receiptPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reçu").font(.headline)
            HStack(spacing: 6) {
                ForEach(ReceiptChoice.allCases) { r in
                    let selected = receipt == r
                    Button { receipt = r; Haptics.tap() } label: {
                        VStack(spacing: 4) {
                            Image(systemName: r.icon).font(.title3)
                            Text(r.label).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(selected ? Color.gain : Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(selected ? Color.gainSoft : .clear, in: .rect(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .padding(6)
            .background(Color.card, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    // MARK: Validate

    private func validate(override: Bool) {
        errorText = nil
        let s = store.data.settings
        if s.requireClient && client == nil { errorText = "Un client est obligatoire (Paramètres > Ventes)."; return }

        var payments: [PaymentPart] = []
        let cashId = store.defaultAccount(for: .cash)?.id
        let mobileId = store.defaultAccount(for: .mobile)?.id
        var change: Double = 0

        switch method {
        case .cash:
            guard let cashId else { return }
            payments = [PaymentPart(method: .cash, accountId: cashId, amount: min(received, total))]
            change = max(0, received - total)
        case .mobile, .card, .transfer:
            guard let id = accountId ?? method.accountKind.flatMap({ store.defaultAccount(for: $0)?.id }) else { return }
            payments = [PaymentPart(method: method, accountId: id, amount: total)]
        case .credit:
            if received > 0, let cashId { payments = [PaymentPart(method: .cash, accountId: cashId, amount: min(received, total))] }
        case .mixed:
            if let cashId, received > 0 { payments.append(PaymentPart(method: .cash, accountId: cashId, amount: received)) }
            if let mobileId, second > 0 { payments.append(PaymentPart(method: .mobile, accountId: mobileId, amount: second)) }
            let paid = received + second
            if paid > total, let i = payments.firstIndex(where: { $0.method == .cash }) {
                change = paid - total
                payments[i].amount = max(0, payments[i].amount - change)
            }
        }

        let paid = payments.reduce(0) { $0 + $1.amount }
        let rest = total - paid
        if rest > 0.5 {
            guard s.allowCredit else { errorText = "La vente à crédit est désactivée."; return }
            guard let client else { errorText = "Choisissez un client : il reste \(Fmt.money(rest)) à payer."; Haptics.warning(); return }
            if !override && store.clientBalance(client.id) + rest > client.creditLimit {
                Haptics.warning()
                limitAlert = true
                return
            }
        }

        amountFocused = false
        let sale = store.recordSale(lines: cart.lines(store: store), client: client, globalDiscount: cart.globalDiscount, payments: payments, note: cart.note)
        changeGiven = change
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { completed = sale }
    }
}
