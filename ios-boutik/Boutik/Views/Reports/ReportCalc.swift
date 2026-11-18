import Foundation

struct ReportBucket: Identifiable { let id: Int; let label: String; let value: Double }
struct ReportTop { let name: String; let qty: Double; let total: Double }

/// All report figures for one period (sales, expenses, chart), shared by the
/// Rapports screen and the PDF so both always show the same numbers.
struct ReportCalc {
    let store: Store
    let period: Period
    let offset: Int
    let interval: DateInterval
    let sales: [Sale]

    init(store: Store, period: Period, offset: Int) {
        self.store = store
        self.period = period
        self.offset = offset
        let interval = period.interval(offset: offset)
        self.interval = interval
        self.sales = store.data.sales.filter { !$0.isCancelled && interval.contains($0.date) }
    }

    var stats: Store.Stats { store.stats(interval) }

    var title: String {
        switch period {
        case .today: return Fmt.day.string(from: interval.start).capitalized
        case .week: return "Semaine du \(Fmt.dayMonth.string(from: interval.start))"
        case .month:
            let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "LLLL yyyy"
            return f.string(from: interval.start).capitalized
        case .year: return String(Calendar.current.component(.year, from: interval.start))
        }
    }

    var buckets: [ReportBucket] {
        let cal = Calendar.current
        switch period {
        case .today:
            return stride(from: 6, through: 22, by: 2).map { h in
                let v = sales.filter { let x = cal.component(.hour, from: $0.date); return x >= h && x < h + 2 }.reduce(0) { $0 + $1.total }
                return ReportBucket(id: h, label: "\(h)h", value: v)
            }
        case .week, .month:
            let days = cal.dateComponents([.day], from: interval.start, to: interval.end).day ?? 7
            let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = period == .week ? "EEE" : "d"
            return (0..<days).map { i in
                let d = cal.date(byAdding: .day, value: i, to: interval.start)!
                let v = sales.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.total }
                return ReportBucket(id: i, label: f.string(from: d), value: v)
            }
        case .year:
            let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "MMM"
            return (0..<12).map { m in
                let d = cal.date(byAdding: .month, value: m, to: interval.start)!
                let v = sales.filter { cal.component(.month, from: $0.date) == m + 1 }.reduce(0) { $0 + $1.total }
                return ReportBucket(id: m, label: f.string(from: d), value: v)
            }
        }
    }

    var topProducts: [ReportTop] {
        var map: [UUID: (String, Double, Double)] = [:]
        for s in sales { for l in s.lines {
            let cur = map[l.productId] ?? (l.name, 0, 0)
            map[l.productId] = (l.name, cur.1 + l.baseQuantity, cur.2 + l.total)
        } }
        return map.values.map { ReportTop(name: $0.0, qty: $0.1, total: $0.2) }.sorted { $0.total > $1.total }.prefix(5).map { $0 }
    }

    var byMethod: [(PaymentMethod, Double)] {
        var map: [PaymentMethod: Double] = [:]
        for s in sales {
            for p in s.payments { map[p.method, default: 0] += p.amount }
            if s.remaining > 0 { map[.credit, default: 0] += s.remaining }
        }
        return map.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var expensesByCat: [(String, Double)] {
        var map: [String: Double] = [:]
        for e in store.data.expenses where interval.contains(e.date) { map[e.category, default: 0] += e.amount }
        return map.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var reportData: ReportData {
        let s = store.data.settings
        return ReportData(
            businessName: s.businessName, address: s.address, phone: s.phone,
            periodTitle: title, stats: stats,
            buckets: buckets.map { ($0.label, $0.value) },
            topProducts: topProducts.map { ($0.name, $0.qty, $0.total) },
            byMethod: byMethod.map { ($0.0.label, $0.1) },
            expenses: expensesByCat.map { ($0.0, $0.1) },
            sales: sales)
    }
}
