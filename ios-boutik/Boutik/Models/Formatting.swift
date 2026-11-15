import Foundation

enum Fmt {
    static var currency = "FCFA"
    static var decimals = 0

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        f.decimalSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    /// "48 500"
    static func amount(_ value: Double) -> String {
        number.minimumFractionDigits = decimals
        number.maximumFractionDigits = decimals
        return number.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// "48 500 FCFA"
    static func money(_ value: Double) -> String { "\(amount(value)) \(currency)" }

    /// "+8 500" / "−3 000"
    static func signed(_ value: Double) -> String {
        value >= 0 ? "+\(amount(value))" : "−\(amount(-value))"
    }

    static func qty(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    static let time: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"; return f
    }()
    static let dayMonth: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM"; return f
    }()
    static let full: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM yyyy 'à' HH:mm"; return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEEE d MMMM"; return f
    }()

    static func shortDate(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return time.string(from: d) }
        if Calendar.current.isDateInYesterday(d) { return "Hier" }
        return dayMonth.string(from: d)
    }

    /// Parse user typed amount "15 000" -> 15000
    static func parse(_ text: String) -> Double {
        let cleaned = text.filter { $0.isNumber || $0 == "," || $0 == "." }.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }
}

enum Period: String, CaseIterable, Identifiable {
    case today, week, month, year
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: "Aujourd'hui"
        case .week: "Semaine"
        case .month: "Mois"
        case .year: "Année"
        }
    }
    var previousLabel: String {
        switch self {
        case .today: "hier"
        case .week: "sem. passée"
        case .month: "mois passé"
        case .year: "an passé"
        }
    }

    func interval(offset: Int = 0, now: Date = Date()) -> DateInterval {
        let cal = Calendar(identifier: .gregorian)
        var c = cal; c.firstWeekday = 2; c.locale = Locale(identifier: "fr_FR")
        let comp: Calendar.Component = switch self {
        case .today: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        let base = c.date(byAdding: comp, value: offset, to: now) ?? now
        return c.dateInterval(of: comp, for: base) ?? DateInterval(start: base, duration: 86_400)
    }
}
