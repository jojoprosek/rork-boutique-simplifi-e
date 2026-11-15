import SwiftUI

struct CartSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var cart: CartModel
    let onPay: () -> Void

    @State private var discountText = ""
    @State private var discountIsPercent = true
    @State private var showClientPicker = false
    @State private var confirmClear = false

    private var showWholesale: Bool { store.data.settings.businessType != .retail }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($cart.items) { $item in
                        if let p = store.product(item.productId) {
                            CartLineRow(item: $item, product: p, showUnits: showWholesale && p.hasPack,
                                        line: store.makeLine(p, quantity: item.quantity, unit: item.unit, client: store.client(cart.clientId), discount: item.discount),
                                        showLineDiscount: store.data.settings.mode == .complete)
                        }
                    }
                    .onDelete { cart.items.remove(atOffsets: $0) }
                }

                Section("Client") {
                    Button { showClientPicker = true } label: {
                        HStack(spacing: 12) {
                            ClientAvatar(client: store.client(cart.clientId), size: 40)
                            Text(store.client(cart.clientId)?.name ?? "Client de passage").foregroundStyle(Color.ink)
                            Spacer()
                            Text("Changer").font(.subheadline.weight(.semibold)).foregroundStyle(Color.gain)
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("0", text: $discountText)
                            .keyboardType(.numberPad)
                            .font(.money(18))
                        Picker("", selection: $discountIsPercent) {
                            Text("%").tag(true)
                            Text(store.data.settings.currency).tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                    TextField(store.data.settings.noteRequiredForDiscount ? "Note (obligatoire pour une remise)" : "Note (facultatif)", text: $cart.note, axis: .vertical)
                } header: {
                    Text("Remise sur tout le panier")
                } footer: {
                    Text("Remise maximale : \(Int(store.data.settings.maxDiscountPercent)) %")
                }

                Section {
                    LabeledContent("Sous-total", value: Fmt.money(subtotal))
                    if cart.globalDiscount > 0 {
                        LabeledContent("Remise", value: "−" + Fmt.money(cart.globalDiscount))
                            .foregroundStyle(Color.loss)
                    }
                    LabeledContent {
                        Text(Fmt.money(cart.total(store: store))).font(.money(22)).foregroundStyle(Color.gain)
                    } label: {
                        Text("À payer").font(.headline)
                    }
                }
            }
            .navigationTitle("Panier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            store.holdCart(cart.lines(store: store), client: store.client(cart.clientId))
                            cart.clear(); dismiss()
                        } label: { Label("Mettre en attente", systemImage: "tray.and.arrow.down") }
                        Button(role: .destructive) { confirmClear = true } label: { Label("Vider le panier", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onPay()
                } label: {
                    Text("Payer \(Fmt.money(cart.total(store: store)))")
                }
                .buttonStyle(BigButtonStyle(kind: .green))
                .disabled(cart.isEmpty || discountInvalid)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .confirmationDialog("Vider le panier ?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Vider", role: .destructive) { cart.clear(); dismiss() }
            }
            .sheet(isPresented: $showClientPicker) {
                ClientPickerView(selected: $cart.clientId)
            }
            .onAppear {
                if cart.globalDiscount > 0 { discountIsPercent = false; discountText = Fmt.amount(cart.globalDiscount) }
            }
            .onChange(of: discountText) { _, _ in applyDiscount() }
            .onChange(of: discountIsPercent) { _, _ in applyDiscount() }
            .onChange(of: cart.items) { _, items in if items.isEmpty { dismiss() } }
        }
        .presentationDetents([.large])
    }

    private var subtotal: Double { cart.lines(store: store).reduce(0) { $0 + $1.total } }

    private var discountInvalid: Bool {
        guard subtotal > 0 else { return false }
        let pct = cart.globalDiscount / subtotal * 100
        if pct > store.data.settings.maxDiscountPercent + 0.01 { return true }
        if store.data.settings.noteRequiredForDiscount && cart.globalDiscount > 0 && cart.note.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }

    private func applyDiscount() {
        let v = Fmt.parse(discountText)
        let raw = discountIsPercent ? subtotal * v / 100 : v
        let cap = subtotal * store.data.settings.maxDiscountPercent / 100
        cart.globalDiscount = min(raw, cap).rounded()
    }
}

struct CartLineRow: View {
    @Binding var item: CartItem
    let product: Product
    let showUnits: Bool
    let line: SaleLine
    let showLineDiscount: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProductThumb(product: product, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.subheadline.weight(.semibold))
                    Text("\(Fmt.money(line.unitPrice)) / \(item.unit == .pack ? product.packName : product.unitName)")
                        .font(.caption).foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Text(Fmt.amount(line.total)).font(.money(17)).foregroundStyle(Color.ink)
            }
            HStack(spacing: 10) {
                if showUnits {
                    Picker("Unité", selection: $item.unit) {
                        Text(product.unitName.capitalized).tag(SaleUnit.piece)
                        Text("\(product.packName.capitalized) (\(Fmt.qty(product.packSize)))").tag(SaleUnit.pack)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                QuantityStepper(value: $item.quantity)
            }
            if showLineDiscount {
                HStack {
                    Text("Remise sur la ligne").font(.caption).foregroundStyle(Color.inkSecondary)
                    Spacer()
                    TextField("0", value: $item.discount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct QuantityStepper: View {
    @Binding var value: Double
    var minimum: Double = 1

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if value > minimum { value -= 1; Haptics.tap() }
            } label: {
                Image(systemName: "minus").frame(width: 44, height: 40)
            }
            .disabled(value <= minimum)
            Text(Fmt.qty(value))
                .font(.money(18))
                .frame(minWidth: 36)
                .contentTransition(.numericText())
            Button {
                value += 1; Haptics.tap()
            } label: {
                Image(systemName: "plus").frame(width: 44, height: 40)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.ink)
        .background(Color.chip, in: .capsule)
        .animation(.snappy, value: value)
    }
}
