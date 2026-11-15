import Foundation

// MARK: - Settings

enum BusinessType: String, Codable, CaseIterable, Identifiable {
    case retail, wholesale, mixed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .retail: "Détaillant"
        case .wholesale: "Grossiste"
        case .mixed: "Les deux (mixte)"
        }
    }
}

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case simple, complete
    var id: String { rawValue }
    var label: String { self == .simple ? "Simple" : "Complet" }
}

enum ThemeChoice: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Automatique"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }
}

enum Plan: String, Codable, CaseIterable, Identifiable {
    case discovery, pro, business
    var id: String { rawValue }
    var label: String {
        switch self {
        case .discovery: "Découverte"
        case .pro: "Pro"
        case .business: "Business"
        }
    }
    var monthlyPrice: Double {
        switch self {
        case .discovery: 2_500
        case .pro: 6_500
        case .business: 15_000
        }
    }
    /// Annual = 10 months (2 months free).
    var yearlyPrice: Double { monthlyPrice * 10 }
    var perks: [String] {
        switch self {
        case .discovery: ["1 boutique", "1 utilisateur", "Jusqu'à 100 produits", "Vente au détail"]
        case .pro: ["1 boutique", "3 utilisateurs", "Produits illimités", "Vente en gros", "Rapports avancés", "Support WhatsApp"]
        case .business: ["Plusieurs boutiques", "Utilisateurs illimités", "Tout Pro", "Support prioritaire"]
        }
    }
}

struct AppSettings: Codable, Equatable {
    var onboarded = false
    var language = "fr"
    var businessName = "Boutique Awa"
    var ownerName = "Awa"
    var phone = ""
    var email = ""
    var country = "Côte d'Ivoire"
    var currency = "FCFA"
    var decimals = 0
    var businessType: BusinessType = .mixed
    var sector = "Alimentation"
    var address = ""
    var taxNumber = ""

    var mode: AppMode = .simple
    var theme: ThemeChoice = .system
    var largeText = false

    var allowCredit = true
    var allowNegativeStock = false
    var requireClient = false
    var maxDiscountPercent: Double = 20
    var noteRequiredForDiscount = false
    var defaultLowStock: Double = 10
    var receiptFooter = "Merci pour votre achat !"
    var reminderTemplate = "Bonjour {nom}, petit rappel : vous devez {montant} à {boutique}. Merci de passer régler dès que possible."

    var pin: String? = nil
    var useBiometrics = false
    var autoLockMinutes = 5

    var syncWifiOnly = false
    var trialStart = Date()
    var plan: Plan? = nil
    var billingYearly = false
    var subscriptionCancelled = false
    var nextSaleNumber = 1
}

// MARK: - Money accounts

enum AccountKind: String, Codable, CaseIterable {
    case cash, mobile, bank, other
    var icon: String {
        switch self {
        case .cash: "banknote"
        case .mobile: "iphone"
        case .bank: "building.columns"
        case .other: "wallet.bifold"
        }
    }
}

struct MoneyAccount: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: AccountKind
    var openingBalance: Double
}

// MARK: - Products & stock

struct PriceTier: Codable, Hashable, Identifiable {
    var id = UUID()
    var minQty: Double
    var price: Double
}

struct Product: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: String
    var imageName: String? = nil
    var photoData: Data? = nil
    var barcode: String = ""
    var reference: String = ""
    var unitName: String = "pièce"
    var packName: String = "carton"
    var packSize: Double = 1
    var costPrice: Double
    var retailPrice: Double
    var wholesalePrice: Double
    var tiers: [PriceTier] = []
    var lowStockAlert: Double = 10
    var isFavorite = false
    var isArchived = false
    var updatedAt = Date()

    var hasPack: Bool { packSize > 1 }
    var margin: Double { retailPrice - costPrice }
    var marginPercent: Double { retailPrice > 0 ? margin / retailPrice * 100 : 0 }
}

enum MovementKind: String, Codable, CaseIterable {
    case initial, purchase, customerReturn, sale, loss, breakage, gift, personal, adjustment, cancel

    var label: String {
        switch self {
        case .initial: "Stock de départ"
        case .purchase: "Achat"
        case .customerReturn: "Retour client"
        case .sale: "Vente"
        case .loss: "Perte"
        case .breakage: "Casse"
        case .gift: "Don"
        case .personal: "Usage personnel"
        case .adjustment: "Inventaire"
        case .cancel: "Vente annulée"
        }
    }
    static let entries: [MovementKind] = [.purchase, .customerReturn]
    static let exits: [MovementKind] = [.loss, .breakage, .gift, .personal]
}

/// Stock is never overwritten: it is the sum of movements.
struct StockMovement: Identifiable, Codable, Hashable {
    var id = UUID()
    var productId: UUID
    var quantity: Double // signed, in base units
    var kind: MovementKind
    var date = Date()
    var note = ""
    var unitCost: Double? = nil
    /// Money account used to pay a stock purchase (nil = not paid / on credit).
    var paidFromAccountId: UUID? = nil
    var user = "Propriétaire"
}

// MARK: - Clients

enum ClientGroup: String, Codable, CaseIterable, Identifiable {
    case retail, wholesale
    var id: String { rawValue }
    var label: String { self == .retail ? "Détail" : "Grossiste" }
}

struct Client: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var phone: String = ""
    var whatsapp: String = ""
    var address: String = ""
    var group: ClientGroup = .retail
    var notes: String = ""
    var creditLimit: Double = 50_000
    var dueDays: Int = 15
    var imageName: String? = nil
    var createdAt = Date()

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Sales

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case cash, mobile, card, transfer, credit, mixed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cash: "Espèces"
        case .mobile: "Mobile money"
        case .card: "Carte"
        case .transfer: "Virement"
        case .credit: "À crédit"
        case .mixed: "Mixte"
        }
    }
    var icon: String {
        switch self {
        case .cash: "banknote"
        case .mobile: "iphone"
        case .card: "creditcard"
        case .transfer: "building.columns"
        case .credit: "person.badge.clock"
        case .mixed: "square.on.square"
        }
    }
    var accountKind: AccountKind? {
        switch self {
        case .cash: .cash
        case .mobile: .mobile
        case .card, .transfer: .bank
        case .credit, .mixed: nil
        }
    }
}

enum SaleUnit: String, Codable { case piece, pack }

struct SaleLine: Identifiable, Codable, Hashable {
    var id = UUID()
    var productId: UUID
    var name: String
    var quantity: Double
    var unit: SaleUnit = .piece
    var unitPrice: Double
    var baseQuantity: Double
    var costPerBase: Double
    var discount: Double = 0

    var total: Double { max(0, quantity * unitPrice - discount) }
    var cost: Double { baseQuantity * costPerBase }
}

struct PaymentPart: Codable, Hashable {
    var method: PaymentMethod
    var accountId: UUID
    var amount: Double
}

struct Sale: Identifiable, Codable, Hashable {
    var id = UUID()
    var number: Int
    var date = Date()
    var clientId: UUID?
    var clientName: String
    var lines: [SaleLine]
    var globalDiscount: Double = 0
    var payments: [PaymentPart]
    var note = ""
    var isCancelled = false
    var cancelReason = ""

    var subtotal: Double { lines.reduce(0) { $0 + $1.total } }
    var total: Double { max(0, subtotal - globalDiscount) }
    var paid: Double { payments.reduce(0) { $0 + $1.amount } }
    var remaining: Double { max(0, total - paid) }
    var cost: Double { lines.reduce(0) { $0 + $1.cost } }
    var itemCount: Double { lines.reduce(0) { $0 + $1.quantity } }
    var numberLabel: String { String(format: "V-%05d", number) }
}

/// A client repays (part of) what they owe.
struct DebtPayment: Identifiable, Codable, Hashable {
    var id = UUID()
    var clientId: UUID
    var amount: Double
    var accountId: UUID
    var date = Date()
}

// MARK: - Money out / in

struct Expense: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Double
    var category: String
    var note: String = ""
    var accountId: UUID
    var date = Date()
    var receiptPhoto: Data? = nil

    static let categories = ["Transport", "Loyer", "Électricité", "Eau", "Salaires", "Marchandises", "Téléphone", "Entretien", "Taxes", "Autre"]
}

struct Income: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Double
    var label: String
    var accountId: UUID
    var date = Date()
}

struct Transfer: Identifiable, Codable, Hashable {
    var id = UUID()
    var fromId: UUID
    var toId: UUID
    var amount: Double
    var date = Date()
}

/// "Je dois" — money the shop owes (supplier, loan…).
struct Payable: Identifiable, Codable, Hashable {
    var id = UUID()
    var creditor: String
    var amount: Double
    var paid: Double = 0
    var dueDate: Date
    var note: String = ""
    var remaining: Double { max(0, amount - paid) }
}

struct PayablePayment: Identifiable, Codable, Hashable {
    var id = UUID()
    var payableId: UUID
    var amount: Double
    var accountId: UUID
    var date = Date()
}

struct HeldCart: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var lines: [SaleLine]
    var clientId: UUID?
    var date = Date()
}

// MARK: - Sync journal

struct PendingOperation: Identifiable, Codable, Hashable {
    var id = UUID()
    var entity: String
    var entityId: UUID
    var action: String
    var date = Date()
}

struct ActivityEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var text: String
}

struct AppData: Codable {
    var settings = AppSettings()
    var accounts: [MoneyAccount] = []
    var products: [Product] = []
    var movements: [StockMovement] = []
    var clients: [Client] = []
    var sales: [Sale] = []
    var debtPayments: [DebtPayment] = []
    var expenses: [Expense] = []
    var incomes: [Income] = []
    var transfers: [Transfer] = []
    var payables: [Payable] = []
    var payablePayments: [PayablePayment] = []
    var heldCarts: [HeldCart] = []
    var pending: [PendingOperation] = []
    var activity: [ActivityEntry] = []
    var lastSync: Date? = nil
}
