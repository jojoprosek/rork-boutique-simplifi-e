import SwiftUI

struct CartItem: Identifiable, Hashable {
    var id: UUID { productId }
    var productId: UUID
    var quantity: Double
    var unit: SaleUnit = .piece
    var discount: Double = 0
}

@Observable
final class CartModel {
    var items: [CartItem] = []
    var clientId: UUID?
    var globalDiscount: Double = 0
    var note = ""

    var isEmpty: Bool { items.isEmpty }

    func quantity(of id: UUID) -> Double { items.first { $0.productId == id }?.quantity ?? 0 }

    func add(_ p: Product) {
        if let i = items.firstIndex(where: { $0.productId == p.id }) {
            items[i].quantity += 1
        } else {
            items.append(CartItem(productId: p.id, quantity: 1))
        }
    }

    func remove(_ p: Product, all: Bool = false) {
        guard let i = items.firstIndex(where: { $0.productId == p.id }) else { return }
        if all || items[i].quantity <= 1 { items.remove(at: i) } else { items[i].quantity -= 1 }
    }

    func clear() {
        items = []; clientId = nil; globalDiscount = 0; note = ""
    }

    func lines(store: Store) -> [SaleLine] {
        let client = store.client(clientId)
        return items.compactMap { item in
            guard let p = store.product(item.productId) else { return nil }
            return store.makeLine(p, quantity: item.quantity, unit: item.unit, client: client, discount: item.discount)
        }
    }

    func total(store: Store) -> Double {
        max(0, lines(store: store).reduce(0) { $0 + $1.total } - globalDiscount)
    }

    func baseQuantity(of id: UUID, store: Store) -> Double {
        guard let item = items.first(where: { $0.productId == id }), let p = store.product(id) else { return 0 }
        return item.unit == .pack ? item.quantity * p.packSize : item.quantity
    }

    func load(_ held: HeldCart) {
        items = held.lines.map { CartItem(productId: $0.productId, quantity: $0.quantity, unit: $0.unit, discount: $0.discount) }
        clientId = held.clientId
    }
}

struct SellView: View {
    @Environment(Store.self) private var store
    @State private var cart = CartModel()
    @State private var search = ""
    @State private var category: String = "Tout"
    @State private var showScanner = false
    @State private var showCart = false
    @State private var showPayment = false
    @State private var warning: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    searchBar
                    categoryChips
                    if filtered.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "Aucun produit", message: "Essayez un autre mot ou ajoutez ce produit.")
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filtered) { p in
                            ProductSaleCard(product: p, inCart: cart.quantity(of: p.id), stock: store.stockOf(p.id),
                                            price: store.unitPrice(for: p, client: store.client(cart.clientId), baseQty: 1)) {
                                add(p)
                            }
                            .contextMenu {
                                if cart.quantity(of: p.id) > 0 {
                                    Button { cart.remove(p) } label: { Label("Retirer un", systemImage: "minus.circle") }
                                    Button(role: .destructive) { cart.remove(p, all: true) } label: { Label("Retirer du panier", systemImage: "trash") }
                                }
                                Button { store.toggleFavorite(p) } label: {
                                    Label(p.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: p.isFavorite ? "star.slash" : "star")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("Vendre")
            .toolbar {
                if !store.data.heldCarts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { heldMenu }
                }
                ToolbarItem(placement: .topBarTrailing) { QuickActionsMenu() }
            }
            .safeAreaInset(edge: .bottom) {
                if !cart.isEmpty {
                    CartBar(count: cart.items.reduce(0) { $0 + $1.quantity }, total: cart.total(store: store),
                            onOpen: { showCart = true }, onPay: { showPayment = true })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: cart.isEmpty)
            .fullScreenCover(isPresented: $showScanner) {
                BarcodeScannerView { code in
                    handleScan(code)
                }
            }
            .sheet(isPresented: $showCart) {
                CartSheet(cart: cart) {
                    showCart = false
                    Task { try? await Task.sleep(for: .milliseconds(450)); showPayment = true }
                }
            }
            .sheet(isPresented: $showPayment) {
                PaymentSheet(cart: cart)
            }
            .alert("Attention", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(warning ?? "") }
        }
    }

    // MARK: Pieces

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.inkSecondary)
                TextField("Chercher un produit", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.inkSecondary) }
                        .accessibilityLabel("Effacer")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.card, in: .capsule)

            Button { showScanner = true } label: {
                Label("Scanner", systemImage: "barcode.viewfinder")
                    .font(.headline)
                    .foregroundStyle(Color.darkButtonText)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Color.darkButton, in: .rect(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var chips: [String] { ["Favoris", "Tout"] + store.categories }

    private var categoryChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { c in
                    let selected = category == c
                    Button {
                        withAnimation(.snappy) { category = c }
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 5) {
                            if c == "Favoris" { Image(systemName: selected ? "star.fill" : "star") }
                            Text(c)
                        }
                        .font(.subheadline.weight(selected ? .bold : .medium))
                        .foregroundStyle(selected ? Color.gain : Color.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(selected ? Color.gainSoft : Color.card, in: .capsule)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var heldMenu: some View {
        Menu {
            Section("Paniers en attente") {
                ForEach(store.data.heldCarts) { held in
                    Button {
                        if !cart.isEmpty { store.holdCart(cart.lines(store: store), client: store.client(cart.clientId)) }
                        cart.clear()
                        cart.load(held)
                        store.removeHeld(held)
                    } label: {
                        Label("\(held.label) · \(Fmt.money(held.lines.reduce(0) { $0 + $1.total }))", systemImage: "cart")
                    }
                }
            }
        } label: {
            Image(systemName: "tray.full")
                .overlay(alignment: .topTrailing) {
                    Text("\(store.data.heldCarts.count)")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .padding(4).background(Color.loss, in: .circle)
                        .offset(x: 8, y: -8)
                }
        }
        .accessibilityLabel("Paniers en attente")
    }

    private var filtered: [Product] {
        var list = store.activeProducts
        if category == "Favoris" { list = list.filter(\.isFavorite) }
        else if category != "Tout" { list = list.filter { $0.category == category } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) || $0.barcode.contains(q) || $0.reference.lowercased().contains(q) }
        }
        return list
    }

    private func add(_ p: Product) {
        let wanted = cart.baseQuantity(of: p.id, store: store) + 1
        if !store.data.settings.allowNegativeStock && wanted > store.stockOf(p.id) {
            Haptics.warning()
            warning = "Il ne reste que \(Fmt.qty(max(0, store.stockOf(p.id)))) \(p.unitName) de « \(p.name) ». Ajoutez du stock ou autorisez le stock négatif dans Paramètres > Ventes."
            return
        }
        Haptics.tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { cart.add(p) }
    }

    private func handleScan(_ code: String) {
        if let p = store.activeProducts.first(where: { $0.barcode == code }) {
            add(p)
        } else {
            Haptics.warning()
            warning = "Aucun produit avec le code \(code). Ajoutez-le depuis l'onglet Produits."
        }
    }
}

struct ProductSaleCard: View {
    let product: Product
    let inCart: Double
    let stock: Double
    let price: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ProductPhoto(product: product)
                    .frame(height: 104)
                    .overlay(alignment: .topTrailing) {
                        if inCart > 0 {
                            Text(Fmt.qty(inCart))
                                .font(.money(16))
                                .foregroundStyle(.white)
                                .frame(minWidth: 34, minHeight: 34)
                                .background(Color.gain, in: .circle)
                                .padding(8)
                                .transition(.scale.combined(with: .opacity))
                                .contentTransition(.numericText())
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink).lineLimit(1)
                    Text(Fmt.money(price)).font(.money(18)).foregroundStyle(Color.gain).lineLimit(1).minimumScaleFactor(0.7)
                    Text("Stock : \(Fmt.qty(stock)) \(product.unitName)\(stock > 1 && !product.unitName.hasSuffix("s") ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(stock <= product.lowStockAlert ? Color.loss : Color.inkSecondary)
                        .lineLimit(1)
                }
                .padding(12)
            }
            .background(Color.card)
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(inCart > 0 ? Color.gain : .clear, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(product.name), \(Fmt.money(price)), stock \(Fmt.qty(stock))")
        .accessibilityHint("Touchez pour ajouter au panier")
    }
}

struct CartBar: View {
    let count: Double
    let total: Double
    let onOpen: () -> Void
    let onPay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "cart").font(.title3)
                    Text("\(Fmt.qty(count)) article\(count > 1 ? "s" : "")").font(.subheadline.weight(.medium))
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 26)
                    Text(Fmt.money(total)).font(.money(20)).lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.darkButtonText)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .accessibilityLabel("Voir le panier")
            Button(action: onPay) {
                Text("Payer")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .frame(height: 48)
                    .background(Color.gain, in: .capsule)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.darkButton, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        .animation(.snappy, value: total)
    }
}
