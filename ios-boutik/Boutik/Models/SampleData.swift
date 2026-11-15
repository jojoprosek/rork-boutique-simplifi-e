import Foundation
import UIKit

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// Demo shop "Boutique Awa" so the app is alive on first launch.
enum SampleData {
    static func defaultAccounts() -> [MoneyAccount] {
        [
            MoneyAccount(name: "Espèces", kind: .cash, openingBalance: 0),
            MoneyAccount(name: "Orange Money", kind: .mobile, openingBalance: 0),
            MoneyAccount(name: "Banque", kind: .bank, openingBalance: 0),
        ]
    }

    struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 10_000) / 10_000
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() * Double(range.count - 0)) % range.count
        }
    }

    static func make(now: Date = Date()) -> AppData {
        var d = AppData()
        d.settings.onboarded = true
        d.settings.trialStart = Calendar.current.date(byAdding: .day, value: -3, to: now)!

        let cash = MoneyAccount(name: "Espèces", kind: .cash, openingBalance: 15_000)
        let om = MoneyAccount(name: "Orange Money", kind: .mobile, openingBalance: 8_000)
        let bank = MoneyAccount(name: "Banque", kind: .bank, openingBalance: 320_000)
        d.accounts = [cash, om, bank]

        func p(_ name: String, _ cat: String, _ img: String, unit: String, pack: String, size: Double,
               cost: Double, retail: Double, wholesale: Double, stock: Double, alert: Double, fav: Bool, code: String) -> (Product, Double) {
            var prod = Product(name: name, category: cat, imageName: img, barcode: code, unitName: unit, packName: pack, packSize: size,
                               costPrice: cost, retailPrice: retail, wholesalePrice: wholesale, lowStockAlert: alert, isFavorite: fav)
            if size > 1 { prod.tiers = [PriceTier(minQty: size * 5, price: (wholesale * 0.97).rounded())] }
            return (prod, stock)
        }

        let catalog: [(Product, Double)] = [
            p("Riz parfumé 5 kg", "Riz et céréales", "p_riz", unit: "sachet", pack: "sac de 5", size: 5, cost: 3_700, retail: 4_500, wholesale: 4_100, stock: 28, alert: 10, fav: true, code: "6111245000012"),
            p("Huile Dinor 1 L", "Huiles", "p_huile", unit: "bouteille", pack: "carton", size: 12, cost: 1_150, retail: 1_400, wholesale: 1_250, stock: 52, alert: 12, fav: true, code: "6181100230015"),
            p("Lait Nido 400 g", "Épicerie", "p_lait", unit: "boîte", pack: "carton", size: 24, cost: 2_750, retail: 3_200, wholesale: 2_950, stock: 17, alert: 8, fav: true, code: "7613035000117"),
            p("Savon Omo 500 g", "Hygiène", "p_savon", unit: "paquet", pack: "carton", size: 20, cost: 650, retail: 850, wholesale: 720, stock: 64, alert: 15, fav: false, code: "8711600000501"),
            p("Sucre 1 kg", "Épicerie", "p_sucre", unit: "sachet", pack: "sac", size: 25, cost: 600, retail: 750, wholesale: 660, stock: 6, alert: 20, fav: true, code: "6150000100018"),
            p("Coca-Cola 1,5 L", "Boissons", "p_soda", unit: "bouteille", pack: "pack de 6", size: 6, cost: 780, retail: 1_000, wholesale: 870, stock: 36, alert: 12, fav: false, code: "5449000054227"),
            p("Tomate concentrée 70 g", "Épicerie", "p_tomate", unit: "boîte", pack: "carton", size: 50, cost: 90, retail: 125, wholesale: 100, stock: 240, alert: 50, fav: false, code: "6181100500019"),
            p("Eau minérale 1,5 L", "Boissons", "p_eau", unit: "bouteille", pack: "pack de 6", size: 6, cost: 280, retail: 400, wholesale: 320, stock: 4, alert: 12, fav: false, code: "6151100400015"),
            p("Spaghetti 500 g", "Riz et céréales", "p_pates", unit: "paquet", pack: "carton", size: 20, cost: 380, retail: 500, wholesale: 430, stock: 3, alert: 10, fav: false, code: "6111001500016"),
        ]

        let start = Calendar.current.date(byAdding: .day, value: -35, to: now)!
        for (prod, qty) in catalog {
            d.products.append(prod)
            // Start with enough stock so that after demo sales the target stock remains.
            d.movements.append(StockMovement(productId: prod.id, quantity: qty, kind: .initial, date: start, unitCost: prod.costPrice))
        }

        let kone = Client(name: "Aminata Koné", phone: "+225 07 08 12 34 56", whatsapp: "+2250708123456", address: "Marché d'Adjamé, allée 4",
                          group: .wholesale, notes: "Grossiste · Marché Adjamé", creditLimit: 200_000, dueDays: 15, imageName: "c_kone")
        let clients = [
            kone,
            Client(name: "Moussa Traoré", phone: "+225 05 44 21 90 11", whatsapp: "+2250544219011", address: "Yopougon", group: .retail, creditLimit: 30_000, dueDays: 7),
            Client(name: "Fatou Diallo", phone: "+225 01 22 33 44 55", whatsapp: "+2250122334455", address: "Cocody", group: .retail, creditLimit: 25_000, dueDays: 7),
            Client(name: "Ibrahim Ouédraogo", phone: "+225 07 77 88 99 00", whatsapp: "+2250777889900", address: "Abobo gare", group: .wholesale, creditLimit: 150_000, dueDays: 30),
            Client(name: "Mariam Bamba", phone: "+225 05 11 22 33 44", whatsapp: "+2250511223344", address: "Treichville", group: .retail, creditLimit: 20_000, dueDays: 7),
        ]
        d.clients = clients

        var rng = LCG(state: 42)
        var number = 1
        func addSale(_ date: Date, client: Client?, items: [(Int, Double, SaleUnit)], pay: PaymentMethod, paidRatio: Double = 1) {
            var lines: [SaleLine] = []
            for (idx, q, unit) in items {
                let prod = catalog[idx].0
                let base = unit == .pack ? q * prod.packSize : q
                var per = prod.retailPrice
                if client?.group == .wholesale { per = prod.wholesalePrice }
                let price = unit == .pack ? per * prod.packSize : per
                lines.append(SaleLine(productId: prod.id, name: prod.name, quantity: q, unit: unit, unitPrice: price, baseQuantity: base, costPerBase: prod.costPrice))
            }
            let total = lines.reduce(0) { $0 + $1.total }
            let acc = pay == .mobile ? om : (pay == .transfer ? bank : cash)
            let paid = (total * paidRatio).rounded()
            let payments = pay == .credit ? (paid > 0 ? [PaymentPart(method: .cash, accountId: cash.id, amount: paid)] : [])
                                          : [PaymentPart(method: pay, accountId: acc.id, amount: total)]
            let sale = Sale(number: number, date: date, clientId: client?.id, clientName: client?.name ?? "Client de passage", lines: lines, payments: payments)
            number += 1
            d.sales.append(sale)
            for l in lines {
                d.movements.append(StockMovement(productId: l.productId, quantity: -l.baseQuantity, kind: .sale, date: date, note: sale.numberLabel))
            }
        }

        let cal = Calendar.current
        func at(_ daysAgo: Int, _ h: Int, _ m: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            return cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
        }

        // History: everyday walk-in sales over the past month.
        for day in stride(from: 30, through: 1, by: -1) {
            let count = 3 + rng.int(0...3)
            for k in 0..<count {
                let idx = rng.int(0...8)
                let idx2 = rng.int(0...8)
                let pay: PaymentMethod = rng.next() < 0.6 ? .cash : .mobile
                let c: Client? = rng.next() < 0.25 ? clients[1 + rng.int(0...3)] : nil
                addSale(at(day, 8 + k * 2, rng.int(0...59)), client: c,
                        items: [(idx, Double(1 + rng.int(0...2)), .piece), (idx2, 1, .piece)], pay: pay)
            }
        }

        // Aminata Koné: wholesale credit history (owes 145 000).
        addSale(at(18, 10, 5), client: kone, items: [(0, 4, .pack), (1, 2, .pack)], pay: .cash)
        addSale(at(13, 11, 20), client: kone, items: [(1, 3, .pack), (3, 2, .pack)], pay: .credit, paidRatio: 0.45)
        addSale(at(3, 9, 40), client: kone, items: [(0, 3, .pack), (6, 1, .pack)], pay: .credit, paidRatio: 0.0)
        // Moussa owes a little and is late.
        addSale(at(12, 17, 10), client: clients[1], items: [(2, 2, .piece), (4, 4, .piece)], pay: .credit, paidRatio: 0)

        // Today's activity.
        addSale(at(0, 8, 52), client: kone, items: [(0, 1, .pack), (1, 1, .pack)], pay: .credit, paidRatio: 0.55)
        addSale(at(0, 9, 28), client: nil, items: [(0, 1, .piece), (1, 2, .piece), (4, 2, .piece)], pay: .cash)
        addSale(at(0, 10, 5), client: clients[2], items: [(2, 1, .piece), (5, 2, .piece)], pay: .mobile)

        d.settings.nextSaleNumber = number

        // Top up stock so the remaining quantities match the catalog targets.
        var current: [UUID: Double] = [:]
        for m in d.movements { current[m.productId, default: 0] += m.quantity }
        for (prod, target) in catalog {
            let diff = target - (current[prod.id] ?? 0)
            if diff != 0 {
                d.movements.append(StockMovement(productId: prod.id, quantity: diff, kind: .purchase, date: cal.date(byAdding: .day, value: -20, to: now)!, unitCost: prod.costPrice))
            }
        }

        // Client repayments
        let koneOwed = d.sales.filter { $0.clientId == kone.id }.reduce(0) { $0 + $1.remaining }
        if koneOwed > 145_000 {
            let extra = koneOwed - 145_000
            d.debtPayments.append(DebtPayment(clientId: kone.id, amount: (extra * 0.6).rounded(), accountId: om.id, date: at(7, 15, 0)))
            d.debtPayments.append(DebtPayment(clientId: kone.id, amount: extra - (extra * 0.6).rounded(), accountId: cash.id, date: at(1, 16, 30)))
        }

        // Expenses
        let expenses: [(Int, Double, String, String, MoneyAccount)] = [
            (0, 3_000, "Transport", "Taxi marchandises", cash),
            (0, 1_500, "Téléphone", "Crédit téléphone", om),
            (2, 12_000, "Électricité", "Facture CIE", om),
            (5, 75_000, "Loyer", "Loyer de la boutique", bank),
            (8, 4_000, "Transport", "Livraison Adjamé", cash),
            (14, 60_000, "Salaires", "Avance vendeur", cash),
            (20, 6_500, "Entretien", "Réparation étagère", cash),
        ]
        for e in expenses {
            d.expenses.append(Expense(amount: e.1, category: e.2, note: e.3, accountId: e.4.id, date: at(e.0, 12, 15)))
        }

        d.payables = [
            Payable(creditor: "SOCOCE Distribution", amount: 120_000, paid: 30_000, dueDate: cal.date(byAdding: .day, value: 6, to: now)!, note: "Livraison huile et riz"),
        ]
        d.payablePayments = [PayablePayment(payableId: d.payables[0].id, amount: 30_000, accountId: bank.id, date: at(9, 10, 0))]

        d.lastSync = now
        return d
    }
}
