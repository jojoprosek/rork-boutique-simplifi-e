import Foundation
import SwiftUI
import Observation

struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    static func == (a: UndoToast, b: UndoToast) -> Bool { a.id == b.id }
}

/// Single source of truth. Everything is stored on the phone first (offline),
/// every change is appended to a sync journal sent when the network is back.
@Observable
final class Store {
    var data: AppData { didSet { didChange() } }
    private(set) var stock: [UUID: Double] = [:]
    var toast: UndoToast?
    var hideAmounts = false

    @ObservationIgnored private var undoSnapshot: AppData?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var suppressJournal = false

    init() {
        if let loaded = Store.load() {
            data = loaded
        } else {
            data = AppData()
        }
        recomputeStock()
        applyFormatting()
    }

    // MARK: Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("boutik-data.json")
    }

    private static func load() -> AppData? {
        guard let raw = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: raw)
    }

    private func didChange() {
        recomputeStock()
        applyFormatting()
        saveTask?.cancel()
        let snapshot = data
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if let encoded = try? JSONEncoder().encode(snapshot) {
                // Encrypted at rest by iOS Data Protection.
                try? encoded.write(to: Store.fileURL, options: [.atomic, .completeFileProtection])
            }
        }
    }

    private func applyFormatting() {
        Fmt.currency = data.settings.currency
        Fmt.decimals = data.settings.decimals
    }

    private func recomputeStock() {
        var map: [UUID: Double] = [:]
        for m in data.movements { map[m.productId, default: 0] += m.quantity }
        stock = map
    }

    // MARK: Mutations with journal + undo

    /// Applies a change, logs it for sync and offers "Annuler" for a few seconds.
    func perform(_ message: String?, entity: String, entityId: UUID, action: String, change: (inout AppData) -> Void) {
        let before = data
        var copy = data
        change(&copy)
        copy.pending.append(PendingOperation(entity: entity, entityId: entityId, action: action))
        copy.activity.insert(ActivityEntry(text: message ?? "\(action) \(entity)"), at: 0)
        if copy.activity.count > 300 { copy.activity.removeLast(copy.activity.count - 300) }
        data = copy
        if let message {
            undoSnapshot = before
            withAnimation(.spring) { toast = UndoToast(message: message) }
        }
    }

    func undo() {
        guard let snap = undoSnapshot else { return }
        var restored = snap
        // Keep the journal honest: the undo itself is an operation to sync.
        restored.pending = data.pending
        restored.pending.append(PendingOperation(entity: "undo", entityId: UUID(), action: "revert"))
        data = restored
        undoSnapshot = nil
        withAnimation(.spring) { toast = nil }
        Haptics.tap()
    }

    func dismissToast(_ t: UndoToast) {
        if toast == t {
            withAnimation(.spring) { toast = nil }
            undoSnapshot = nil
        }
    }

    // MARK: Lookups

    var settings: AppSettings {
        get { data.settings }
        set { data.settings = newValue }
    }

    func product(_ id: UUID) -> Product? { data.products.first { $0.id == id } }
    func client(_ id: UUID?) -> Client? { guard let id else { return nil }; return data.clients.first { $0.id == id } }
    func account(_ id: UUID) -> MoneyAccount? { data.accounts.first { $0.id == id } }
    func stockOf(_ id: UUID) -> Double { stock[id] ?? 0 }

    var activeProducts: [Product] { data.products.filter { !$0.isArchived } }
    var categories: [String] { Array(Set(activeProducts.map(\.category))).sorted() }

    func defaultAccount(for kind: AccountKind) -> MoneyAccount? {
        data.accounts.first { $0.kind == kind } ?? data.accounts.first
    }

    var lowStockProducts: [Product] {
        activeProducts.filter { stockOf($0.id) <= $0.lowStockAlert }
    }

    // MARK: Money

    func balance(of account: MoneyAccount) -> Double {
        let id = account.id
        var b = account.openingBalance
        for s in data.sales where !s.isCancelled {
            for p in s.payments where p.accountId == id { b += p.amount }
        }
        b += data.debtPayments.filter { $0.accountId == id }.reduce(0) { $0 + $1.amount }
        b += data.incomes.filter { $0.accountId == id }.reduce(0) { $0 + $1.amount }
        b -= data.expenses.filter { $0.accountId == id }.reduce(0) { $0 + $1.amount }
        b -= data.payablePayments.filter { $0.accountId == id }.reduce(0) { $0 + $1.amount }
        for m in data.movements where m.paidFromAccountId == id { b -= m.quantity * (m.unitCost ?? 0) }
        for t in data.transfers {
            if t.fromId == id { b -= t.amount }
            if t.toId == id { b += t.amount }
        }
        return b
    }

    var totalCash: Double { data.accounts.reduce(0) { $0 + balance(of: $1) } }

    func clientBalance(_ id: UUID) -> Double {
        let owed = data.sales.filter { $0.clientId == id && !$0.isCancelled }.reduce(0) { $0 + $1.remaining }
        let repaid = data.debtPayments.filter { $0.clientId == id }.reduce(0) { $0 + $1.amount }
        return max(0, owed - repaid)
    }

    /// Due date of the oldest unpaid credit.
    func clientDueDate(_ c: Client) -> Date? {
        guard clientBalance(c.id) > 0 else { return nil }
        let credit = data.sales.filter { $0.clientId == c.id && !$0.isCancelled && $0.remaining > 0 }
            .sorted { $0.date > $1.date }
        // Walk from newest credit down until the remaining balance is covered.
        var left = clientBalance(c.id)
        var oldest: Date?
        for s in credit where left > 0 {
            left -= s.remaining
            oldest = s.date
        }
        guard let oldest else { return nil }
        return Calendar.current.date(byAdding: .day, value: c.dueDays, to: oldest)
    }

    func isOverdue(_ c: Client) -> Bool {
        guard let d = clientDueDate(c) else { return false }
        return d < Date()
    }

    var totalOwedToMe: Double { data.clients.reduce(0) { $0 + clientBalance($1.id) } }
    var totalIOwe: Double { data.payables.reduce(0) { $0 + $1.remaining } }

    // MARK: Period stats

    struct Stats {
        var sold: Double = 0
        var costOfGoods: Double = 0
        var expenses: Double = 0
        var salesCount = 0
        var spent: Double { costOfGoods + expenses }
        var left: Double { sold - spent }
    }

    func stats(_ interval: DateInterval) -> Stats {
        var s = Stats()
        for sale in data.sales where !sale.isCancelled && interval.contains(sale.date) {
            s.sold += sale.total
            s.costOfGoods += sale.cost
            s.salesCount += 1
        }
        s.expenses = data.expenses.filter { interval.contains($0.date) }.reduce(0) { $0 + $1.amount }
        return s
    }

    var stockValueAtCost: Double {
        activeProducts.reduce(0) { $0 + max(0, stockOf($1.id)) * $1.costPrice }
    }
    var stockValueAtPrice: Double {
        activeProducts.reduce(0) { $0 + max(0, stockOf($1.id)) * $1.retailPrice }
    }

    // MARK: Pricing

    /// Price per *base unit* for a product, given the client and quantity (in base units).
    func unitPrice(for p: Product, client: Client?, baseQty: Double) -> Double {
        var price = p.retailPrice
        let wholesaleAllowed = data.settings.businessType != .retail
        if wholesaleAllowed && (client?.group == .wholesale || data.settings.businessType == .wholesale) {
            price = p.wholesalePrice
        }
        if wholesaleAllowed {
            for tier in p.tiers.sorted(by: { $0.minQty < $1.minQty }) where baseQty >= tier.minQty {
                price = min(price, tier.price)
            }
        }
        return price
    }

    func makeLine(_ p: Product, quantity: Double, unit: SaleUnit, client: Client?, discount: Double = 0) -> SaleLine {
        let base = unit == .pack ? quantity * p.packSize : quantity
        let perBase = unitPrice(for: p, client: client, baseQty: base)
        let displayUnitPrice = unit == .pack ? perBase * p.packSize : perBase
        return SaleLine(productId: p.id, name: p.name, quantity: quantity, unit: unit,
                        unitPrice: displayUnitPrice, baseQuantity: base, costPerBase: p.costPrice, discount: discount)
    }

    // MARK: Sales

    @discardableResult
    func recordSale(lines: [SaleLine], client: Client?, globalDiscount: Double, payments: [PaymentPart], note: String) -> Sale {
        let number = data.settings.nextSaleNumber
        let sale = Sale(number: number, clientId: client?.id, clientName: client?.name ?? "Client de passage",
                        lines: lines, globalDiscount: globalDiscount, payments: payments.filter { $0.amount > 0 }, note: note)
        perform("Vente de \(Fmt.money(sale.total)) enregistrée", entity: "sale", entityId: sale.id, action: "create") { d in
            d.settings.nextSaleNumber += 1
            d.sales.append(sale)
            for l in lines {
                d.movements.append(StockMovement(productId: l.productId, quantity: -l.baseQuantity, kind: .sale, note: sale.numberLabel))
            }
        }
        Haptics.success()
        return sale
    }

    func cancelSale(_ sale: Sale, reason: String) {
        perform("Vente \(sale.numberLabel) annulée", entity: "sale", entityId: sale.id, action: "cancel") { d in
            guard let i = d.sales.firstIndex(where: { $0.id == sale.id }) else { return }
            d.sales[i].isCancelled = true
            d.sales[i].cancelReason = reason
            for l in sale.lines {
                d.movements.append(StockMovement(productId: l.productId, quantity: l.baseQuantity, kind: .cancel, note: sale.numberLabel))
            }
        }
    }

    // MARK: Products & stock

    func saveProduct(_ p: Product, initialStock: Double? = nil) {
        var p = p
        p.updatedAt = Date()
        let exists = data.products.contains { $0.id == p.id }
        perform(exists ? nil : "Produit « \(p.name) » ajouté", entity: "product", entityId: p.id, action: exists ? "update" : "create") { d in
            if let i = d.products.firstIndex(where: { $0.id == p.id }) {
                d.products[i] = p
            } else {
                d.products.append(p)
                if let initialStock, initialStock != 0 {
                    d.movements.append(StockMovement(productId: p.id, quantity: initialStock, kind: .initial, unitCost: p.costPrice))
                }
            }
        }
    }

    func setArchived(_ p: Product, _ archived: Bool) {
        perform(archived ? "« \(p.name) » archivé" : "« \(p.name) » réactivé", entity: "product", entityId: p.id, action: "archive") { d in
            if let i = d.products.firstIndex(where: { $0.id == p.id }) { d.products[i].isArchived = archived }
        }
    }

    func toggleFavorite(_ p: Product) {
        perform(nil, entity: "product", entityId: p.id, action: "favorite") { d in
            if let i = d.products.firstIndex(where: { $0.id == p.id }) { d.products[i].isFavorite.toggle() }
        }
        Haptics.tap()
    }

    /// Adds a stock movement. Purchases update the weighted average cost.
    func addMovement(product: Product, quantity: Double, kind: MovementKind, unitCost: Double?, paidFrom: UUID?, onCreditTo creditor: String?, note: String) {
        let signed = MovementKind.exits.contains(kind) ? -abs(quantity) : quantity
        let current = stockOf(product.id)
        perform("\(kind.label) : \(Fmt.qty(abs(signed))) × \(product.name)", entity: "stock", entityId: product.id, action: kind.rawValue) { d in
            d.movements.append(StockMovement(productId: product.id, quantity: signed, kind: kind, note: note, unitCost: unitCost, paidFromAccountId: paidFrom))
            if kind == .purchase, let unitCost, unitCost > 0, let i = d.products.firstIndex(where: { $0.id == product.id }) {
                let oldQty = max(0, current)
                let newCost = (oldQty * d.products[i].costPrice + quantity * unitCost) / max(1, oldQty + quantity)
                d.products[i].costPrice = newCost.rounded()
                if let creditor, !creditor.isEmpty {
                    d.payables.append(Payable(creditor: creditor, amount: quantity * unitCost,
                                              dueDate: Calendar.current.date(byAdding: .day, value: 30, to: Date())!,
                                              note: "Achat \(product.name)"))
                }
            }
        }
    }

    /// Inventory count: records the difference as an adjustment movement.
    func recordCount(product: Product, counted: Double) {
        let diff = counted - stockOf(product.id)
        guard diff != 0 else { return }
        perform("Inventaire : écart de \(Fmt.signed(diff)) sur \(product.name)", entity: "stock", entityId: product.id, action: "count") { d in
            d.movements.append(StockMovement(productId: product.id, quantity: diff, kind: .adjustment, note: "Comptage : \(Fmt.qty(counted))"))
        }
    }

    // MARK: Clients

    func saveClient(_ c: Client) {
        let exists = data.clients.contains { $0.id == c.id }
        perform(exists ? nil : "Client « \(c.name) » ajouté", entity: "client", entityId: c.id, action: exists ? "update" : "create") { d in
            if let i = d.clients.firstIndex(where: { $0.id == c.id }) { d.clients[i] = c } else { d.clients.append(c) }
        }
    }

    func deleteClient(_ c: Client) {
        perform("Client « \(c.name) » supprimé", entity: "client", entityId: c.id, action: "delete") { d in
            d.clients.removeAll { $0.id == c.id }
        }
    }

    func recordDebtPayment(client: Client, amount: Double, account: MoneyAccount) {
        let p = DebtPayment(clientId: client.id, amount: amount, accountId: account.id)
        perform("\(client.name) a payé \(Fmt.money(amount))", entity: "debtPayment", entityId: p.id, action: "create") { d in
            d.debtPayments.append(p)
        }
        Haptics.success()
    }

    // MARK: Money

    func addExpense(_ e: Expense) {
        perform("Dépense de \(Fmt.money(e.amount)) enregistrée", entity: "expense", entityId: e.id, action: "create") { d in
            d.expenses.append(e)
        }
    }

    func deleteExpense(_ e: Expense) {
        perform("Dépense supprimée", entity: "expense", entityId: e.id, action: "delete") { d in
            d.expenses.removeAll { $0.id == e.id }
        }
    }

    func addIncome(_ i: Income) {
        perform("Entrée de \(Fmt.money(i.amount)) enregistrée", entity: "income", entityId: i.id, action: "create") { d in
            d.incomes.append(i)
        }
    }

    func addTransfer(_ t: Transfer) {
        perform("Transfert de \(Fmt.money(t.amount)) fait", entity: "transfer", entityId: t.id, action: "create") { d in
            d.transfers.append(t)
        }
    }

    func saveAccount(_ a: MoneyAccount) {
        perform(nil, entity: "account", entityId: a.id, action: "save") { d in
            if let i = d.accounts.firstIndex(where: { $0.id == a.id }) { d.accounts[i] = a } else { d.accounts.append(a) }
        }
    }

    func addPayable(_ p: Payable) {
        perform("Dette envers \(p.creditor) ajoutée", entity: "payable", entityId: p.id, action: "create") { d in
            d.payables.append(p)
        }
    }

    func payPayable(_ p: Payable, amount: Double, account: MoneyAccount) {
        let pay = PayablePayment(payableId: p.id, amount: amount, accountId: account.id)
        perform("\(Fmt.money(amount)) payés à \(p.creditor)", entity: "payable", entityId: p.id, action: "pay") { d in
            d.payablePayments.append(pay)
            if let i = d.payables.firstIndex(where: { $0.id == p.id }) { d.payables[i].paid += amount }
        }
    }

    // MARK: Held carts

    func holdCart(_ lines: [SaleLine], client: Client?) {
        let n = data.heldCarts.count + 1
        let cart = HeldCart(label: client?.name ?? "Panier \(n)", lines: lines, clientId: client?.id)
        data.heldCarts.append(cart)
        withAnimation(.spring) { toast = UndoToast(message: "Panier mis en attente") }
        undoSnapshot = nil
    }

    func removeHeld(_ cart: HeldCart) { data.heldCarts.removeAll { $0.id == cart.id } }

    // MARK: Subscription

    var trialDaysLeft: Int {
        let end = Calendar.current.date(byAdding: .day, value: 14, to: data.settings.trialStart) ?? Date()
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
    }

    // MARK: Reset

    func loadDemo() {
        var d = SampleData.make()
        d.settings.onboarded = data.settings.onboarded
        d.settings.businessName = data.settings.businessName.isEmpty ? d.settings.businessName : data.settings.businessName
        d.settings.pin = data.settings.pin
        d.settings.useBiometrics = data.settings.useBiometrics
        data = d
    }

    func startEmpty(keeping s: AppSettings) {
        var d = AppData()
        d.settings = s
        d.accounts = SampleData.defaultAccounts()
        data = d
    }
}
