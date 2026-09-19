import Foundation

enum Money {
    static let maximumCents = 99_999_999_999

    static func parse(_ text: String) -> Int? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.range(of: #"^-?\$?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        let cleaned = input
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let number = NSDecimalNumber(decimal: decimal * 100)
        guard number.doubleValue.isFinite, abs(number.doubleValue) <= Double(maximumCents) else { return nil }
        return number.intValue
    }

    static func format(_ cents: Int, decimals: Bool = true) -> String {
        (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(decimals ? 2 : 0)))
    }

    static func input(_ cents: Int) -> String { String(format: "%.2f", Double(cents) / 100) }
}

enum SpendingCategory: String, Codable, CaseIterable, Identifiable {
    case food = "Food & drink"
    case groceries = "Groceries"
    case transport = "Transport"
    case shopping = "Shopping"
    case education = "Education"
    case home = "Home & bills"
    case fun = "Entertainment"
    case health = "Health"
    case other = "Other"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .food: "cup.and.saucer.fill"
        case .groceries: "carrot.fill"
        case .transport: "tram.fill"
        case .shopping: "bag.fill"
        case .education: "books.vertical.fill"
        case .home: "house.fill"
        case .fun: "sparkles.tv.fill"
        case .health: "heart.fill"
        case .other: "ellipsis"
        }
    }

    static func infer(from merchant: String) -> Self {
        let name = merchant.lowercased()
        let rules: [(Self, [String])] = [
            (.groceries, ["grocery", "groceries", "trader joe", "whole foods", "aldi", "market"]),
            (.food, ["coffee", "cafe", "café", "starbucks", "chipotle", "pizza", "restaurant", "bakery"]),
            (.transport, ["uber", "lyft", "metro", "transit", "shell", "gas", "mta"]),
            (.education, ["book", "school", "tuition", "supplies", "course"]),
            (.home, ["rent", "electric", "internet", "utility", "utilities"]),
            (.fun, ["spotify", "netflix", "cinema", "movie", "concert"]),
            (.health, ["pharmacy", "cvs", "doctor", "gym"]),
            (.shopping, ["target", "amazon", "store", "uniqlo", "nike"])
        ]
        return rules.first { $0.1.contains(where: name.contains) }?.0 ?? .other
    }

    static func fromPlaidPrimary(_ raw: String?) -> Self? {
        guard let raw else { return nil }
        switch raw {
        case "GROCERIES": return .groceries
        case "FOOD_AND_DRINK": return .food
        case "TRANSPORTATION", "TRAVEL": return .transport
        case "GENERAL_MERCHANDISE", "RETAIL": return .shopping
        case "RENT_AND_UTILITIES", "HOME_IMPROVEMENT": return .home
        case "ENTERTAINMENT": return .fun
        case "MEDICAL", "PERSONAL_CARE": return .health
        case "GENERAL_SERVICES", "GOVERNMENT_AND_NON_PROFIT", "LOAN_PAYMENTS", "BANK_FEES", "TRANSFER_IN", "TRANSFER_OUT", "INCOME": return .other
        default: return nil
        }
    }
}

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Expense"
    case income = "Income"
    var id: String { rawValue }
}

enum TransactionSource: String, Codable { case manual = "Manual", receipt = "Receipt", csv = "Spreadsheet", sample = "Sample", plaid = "Bank" }

struct BankAccount: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var detail: String
    var symbol: String = "building.columns.fill"
    var openingBalance: Int = 0
    var colorIndex: Int = 0
}

/// A reviewed receipt reading kept alongside the purchase it belongs to. The original
/// image is never stored — only the fields the user confirmed and the extracted text.
struct ReceiptAttachment: Codable, Equatable {
    var scannedAt: Date = Date()
    var merchant: String
    var total: Int?
    var purchasedAt: Date?
    var text: String
    var mappedManually: Bool = false
}

struct Transaction: Identifiable, Codable, Equatable {
    var id = UUID()
    var merchant: String
    var amount: Int
    var date: Date
    var category: SpendingCategory
    var accountID: UUID
    var kind: TransactionKind = .expense
    var source: TransactionSource = .manual
    var note: String = ""
    var receipt: ReceiptAttachment?
}

extension Transaction {
    /// The bank a synced row came from. A sync pulls every linked institution into one local
    /// account, so the institution — which the sync records in the note — is the only thing
    /// separating one bank's transactions from another's.
    var institutionName: String? {
        guard source == .plaid else { return nil }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return nil }
        let pending = "Pending at "
        return note.hasPrefix(pending) ? String(note.dropFirst(pending.count)) : note
    }

    /// Where a row came from, for grouping and review: the bank when there is one, else how it
    /// was added.
    var originName: String { institutionName ?? source.rawValue }

    /// Bank sync, CSV rows, and receipts carry a calendar date but no clock time, so they land on
    /// midnight. Rendering "12:00 AM" for those would invent precision the source never had.
    var recordedTime: Date? {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return parts.hour == 0 && parts.minute == 0 ? nil : date
    }
}

struct FinanceData: Codable, Equatable {
    /// v2 added `Transaction.receipt`. Older saves decode unchanged because the field is optional.
    /// v3 repaired bank rows stored a day early by the UTC date-parsing bug.
    static let currentSchemaVersion = 3

    var schemaVersion: Int = currentSchemaVersion
    var name: String = "friend"
    var accounts: [BankAccount] = []
    var transactions: [Transaction] = []
    var isDemo: Bool = false

    static func empty() -> Self {
        FinanceData(accounts: [BankAccount(name: "Everyday", detail: "Personal account")])
    }

    static func sample(now: Date = Date()) -> Self {
        let checking = BankAccount(name: "Everyday", detail: "Checking", openingBalance: 185_000, colorIndex: 0)
        let student = BankAccount(name: "Campus", detail: "Student account", openingBalance: 62_000, colorIndex: 1)
        let cash = BankAccount(name: "Cash", detail: "In your pocket", symbol: "banknote.fill", openingBalance: 15_000, colorIndex: 2)
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: now)!.start
        let today = calendar.component(.day, from: now)
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: max(0, min(n, today) - 1), to: month)! }
        let rows: [(String, Int, Int, SpendingCategory, UUID)] = [
            ("Monthly rent", 65_000, 1, .home, checking.id),
            ("Trader Joe’s", 6_842, 3, .groceries, checking.id),
            ("Campus Bookstore", 8_950, 4, .education, student.id),
            ("Metro pass", 3_400, 5, .transport, checking.id),
            ("Spotify", 599, 6, .fun, checking.id),
            ("Sunday Coffee", 675, 7, .food, cash.id),
            ("Whole Foods", 5_236, 8, .groceries, checking.id),
            ("Uniqlo", 4_990, 10, .shopping, student.id),
            ("Chipotle", 1_485, 11, .food, checking.id),
            ("Campus print shop", 1_200, 12, .education, student.id),
            ("Corner Café", 850, 13, .food, cash.id),
            ("Trader Joe’s", 7_812, 14, .groceries, checking.id),
            ("Cinema night", 1_600, 15, .fun, student.id),
            ("Sunday Coffee", 625, 16, .food, checking.id),
            ("Target", 3_248, 17, .shopping, student.id),
            ("Sweetgreen", 1_675, 18, .food, checking.id)
        ]
        var transactions = rows.map { Transaction(merchant: $0.0, amount: $0.1, date: day($0.2), category: $0.3, accountID: $0.4, source: .sample) }
        transactions.append(Transaction(merchant: "Campus job", amount: 145_000, date: day(2), category: .other, accountID: checking.id, kind: .income, source: .sample))
        for offset in 1...2 {
            let previous = calendar.date(byAdding: .month, value: -offset, to: month)!
            for (index, row) in rows.enumerated() {
                transactions.append(Transaction(merchant: row.0, amount: row.1 + (index % 3) * 120 * offset,
                    date: calendar.date(byAdding: .day, value: row.2 - 1, to: previous)!, category: row.3, accountID: row.4, source: .sample))
            }
        }
        return FinanceData(accounts: [checking, student, cash], transactions: transactions, isDemo: true)
    }
}

enum DuplicateDetector {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }

    /// Conservative candidates only. Review never silently removes transactions.
    static func matches(_ lhs: Transaction, _ rhs: Transaction, calendar: Calendar = .current) -> Bool {
        lhs.id != rhs.id && lhs.amount == rhs.amount && lhs.kind == rhs.kind && lhs.accountID == rhs.accountID
            && calendar.isDate(lhs.date, inSameDayAs: rhs.date) && normalized(lhs.merchant) == normalized(rhs.merchant)
    }
}
