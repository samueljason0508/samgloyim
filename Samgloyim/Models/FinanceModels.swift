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

/// The top level of the bucketing system: what the donut, the filters and the flow diagram speak.
///
/// It mirrors Plaid's spending primaries so that every bank row has somewhere to land, plus the two
/// splits this app has always cared about — groceries out of food, travel out of transport. New
/// cases are appended, never inserted: raw values are persisted in the save file and matched by CSV
/// import, and `.other` must keep its meaning of "nothing decided this yet".
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
    case travel = "Travel"
    case personalCare = "Personal care"
    case subscriptions = "Subscriptions"
    case people = "People"
    case fees = "Fees & interest"
    case government = "Government"
    case services = "Services"

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
        case .travel: "airplane"
        case .personalCare: "scissors"
        case .subscriptions: "repeat.circle.fill"
        case .people: "person.2.fill"
        case .fees: "percent"
        case .government: "building.columns.fill"
        case .services: "wrench.and.screwdriver.fill"
        }
    }

    static func infer(from merchant: String) -> Self {
        let name = merchant.lowercased()
        // Ordered, first match wins. Anything narrow goes above anything that could swallow it:
        // "late fee" before food's "cafe"-alikes, "amex send" before any shopping rule.
        let rules: [(Self, [String])] = [
            (.people, ["zelle", "venmo", "cash app", "amex send", "paypal transfer"]),
            (.fees, ["late fee", "interest charge", "atm fee", "overdraft", "service charge", "foreign transaction fee"]),
            (.government, ["dmv", "irs", "tax payment", "court", "usps", "post office", "city of", "county"]),
            (.subscriptions, ["spotify", "netflix", "anthropic", "openai", "subscription", "hulu", "disney+", "icloud", "patreon"]),
            (.groceries, ["grocery", "groceries", "trader joe", "whole foods", "aldi", "market"]),
            (.food, ["coffee", "cafe", "café", "starbucks", "chipotle", "pizza", "restaurant", "bakery"]),
            (.travel, ["airline", "airways", "hotel", "motel", "airbnb", "expedia", "flight"]),
            (.transport, ["uber", "lyft", "metro", "transit", "shell", "gas", "mta", "parking", "toll"]),
            (.education, ["book", "school", "tuition", "supplies", "course"]),
            (.home, ["rent", "electric", "internet", "utility", "utilities"]),
            (.fun, ["cinema", "movie", "concert", "steam", "arcade"]),
            (.personalCare, ["salon", "barber", "spa", "laundry", "dry clean"]),
            (.health, ["pharmacy", "cvs", "doctor", "dental", "gym", "clinic"]),
            (.services, ["insurance", "storage", "shipping", "legal", "childcare", "repair"]),
            (.shopping, ["target", "amazon", "store", "uniqlo", "nike"])
        ]
        return rules.first { $0.1.contains(where: name.contains) }?.0 ?? .other
    }

    /// The whole pipeline in one call: the bank's answer, unless the bank has admitted it does not
    /// have one.
    ///
    /// Plaid's `*_OTHER_*` values are its own catch-alls — "other general services" says little more
    /// than nothing — and a merchant name the keyword table recognises beats them. Anthropic arrives
    /// as GENERAL_SERVICES_OTHER_GENERAL_SERVICES and is plainly a subscription.
    static func resolve(primary: String?, detailed: String?, merchant: String) -> Self {
        if let detailed, detailed.contains("_OTHER_") {
            let guess = infer(from: merchant)
            if guess != .other { return guess }
        }
        return fromPlaid(primary: primary, detailed: detailed) ?? infer(from: merchant)
    }

    /// Where a bank row belongs, resolved in three passes: the detailed value when this app files
    /// it somewhere other than its primary would, then the primary — all sixteen of them, so no
    /// row can fall through — and finally nil, which leaves the merchant name to `infer`.
    static func fromPlaid(primary: String?, detailed: String?) -> Self? {
        if let detailed, let override = detailedOverrides[detailed] { return override }
        guard let primary else { return nil }
        return primaries[primary]
    }

    /// Only the detailed values this app disagrees with its own primary about. Everything else is
    /// covered by the primary table, which is the point of having one.
    private static let detailedOverrides: [String: Self] = [
        // The app has always kept groceries apart from eating out.
        "FOOD_AND_DRINK_GROCERIES": .groceries,
        // A streaming bill is a subscription, not a night out.
        "ENTERTAINMENT_TV_AND_MOVIES": .subscriptions,
        "ENTERTAINMENT_MUSIC_AND_AUDIO": .subscriptions,
        // GENERAL_SERVICES is the widest primary Plaid has; these four are not "services".
        "GENERAL_SERVICES_EDUCATION": .education,
        "GENERAL_SERVICES_AUTOMOTIVE": .transport,
        "GENERAL_SERVICES_CHILDCARE": .services,
        "GENERAL_SERVICES_INSURANCE": .services,
        // A loan payment is filed by what the loan bought.
        "LOAN_PAYMENTS_MORTGAGE_PAYMENT": .home,
        "LOAN_PAYMENTS_STUDENT_LOAN_PAYMENT": .education,
        "LOAN_PAYMENTS_CAR_PAYMENT": .transport,
        // Phone and internet are bills; the rest of RENT_AND_UTILITIES already is.
        "RENT_AND_UTILITIES_INTERNET_AND_CABLE": .home,
        "RENT_AND_UTILITIES_TELEPHONE": .home,
        // A vet bill is the pet's health, not the owner's — but it is medical spending either way.
        "MEDICAL_VETERINARY_SERVICES": .health
    ]

    /// Every primary Plaid publishes. Total by construction: adding a primary to this table is the
    /// only thing needed for a whole new branch of the taxonomy to stop landing in Other.
    private static let primaries: [String: Self] = [
        "FOOD_AND_DRINK": .food,
        "GROCERIES": .groceries,
        "TRANSPORTATION": .transport,
        "TRAVEL": .travel,
        "GENERAL_MERCHANDISE": .shopping,
        "RETAIL": .shopping,
        "HOME_IMPROVEMENT": .home,
        "RENT_AND_UTILITIES": .home,
        "LOAN_PAYMENTS": .home,
        "MEDICAL": .health,
        "PERSONAL_CARE": .personalCare,
        "ENTERTAINMENT": .fun,
        "GENERAL_SERVICES": .services,
        "GOVERNMENT_AND_NON_PROFIT": .government,
        "BANK_FEES": .fees,
        // A self-transfer never reaches a spending total — `isTransfer` removes it — so the only
        // TRANSFER_OUT rows that get here are the ones paying a person.
        "TRANSFER_OUT": .people,
        // Income is excluded from the donut, so its category is cosmetic.
        "TRANSFER_IN": .other,
        "INCOME": .other
    ]

    /// Issuers whose person-to-person service the bank reports as a move between the user's own
    /// accounts. Amex Send is Venmo-style — the money leaves for someone else — whatever Plaid
    /// labels it, so the merchant is the only thing that tells the truth here.
    private static func sendsMoneyToPeople(_ merchant: String) -> Bool {
        merchant.localizedCaseInsensitiveContains("amex send")
    }

    /// Money moving between the user's own accounts, or paying off a card whose purchases are
    /// already recorded. Counting these as spending double-counts and, in the case of a large
    /// account transfer, swamps every real number on the screen.
    ///
    /// Paying a person is not one of these. Zelle, Venmo and the like leave under `TRANSFER_OUT`
    /// beside genuine self-transfers, so the outgoing side is decided on the detailed category:
    /// only a move to the user's own account, savings, investments or cash is excluded. Incoming
    /// transfers stay excluded whatever their detail — a repayment or a deposit from the user's
    /// other bank is not earnings, and treating it as income would overstate what they made.
    static func isTransfer(primary: String?, detailed: String?, merchant: String = "") -> Bool {
        if detailed == "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT" { return true }
        guard let primary else { return false }
        if primary == "TRANSFER_IN" { return true }
        guard primary == "TRANSFER_OUT" else { return false }
        if sendsMoneyToPeople(merchant) { return false }
        switch detailed {
        case "TRANSFER_OUT_ACCOUNT_TRANSFER", "TRANSFER_OUT_SAVINGS",
             "TRANSFER_OUT_INVESTMENT_AND_RETIREMENT_FUNDS", "TRANSFER_OUT_WITHDRAWAL":
            return true
        default:
            // Without a detailed category there is nothing to tell the two apart, so assume the
            // common case rather than inflating spending with the user's own money.
            return detailed == nil
        }
    }
}

/// The second level: what the bank itself called the purchase, kept as the string it sent.
///
/// Plaid publishes 117 of these and adds more over time. Nothing in the app branches on one — they
/// are displayed, grouped and counted — so an enum would be 117 hand-written cases that go stale
/// the day the taxonomy grows, and a string costs nothing and never needs maintaining.
enum SpendingDetail {
    /// "FOOD_AND_DRINK_COFFEE" reads as "Coffee"; the primary prefix is already the category above
    /// it, so repeating it is noise. A value that is only its own primary spelt twice
    /// ("..._OTHER_FOOD_AND_DRINK") keeps the word "Other" and drops the echo.
    static func name(for raw: String) -> String {
        let words = raw.split(separator: "_").map(String.init)
        guard !words.isEmpty else { return raw }
        if let index = words.firstIndex(of: "OTHER") {
            let tail = words[(index + 1)...].joined(separator: " ")
            return sentenceCased(tail.isEmpty ? words.joined(separator: " ") : "OTHER " + tail)
        }
        // Drop the longest known primary that prefixes it; what remains is the useful part.
        for primary in knownPrefixes where raw.hasPrefix(primary + "_") {
            return sentenceCased(String(raw.dropFirst(primary.count + 1)))
        }
        return sentenceCased(raw)
    }

    private static let knownPrefixes = ["GOVERNMENT_AND_NON_PROFIT", "GENERAL_MERCHANDISE", "RENT_AND_UTILITIES",
                                        "INVESTMENT_AND_RETIREMENT", "HOME_IMPROVEMENT", "TRANSPORTATION",
                                        "FOOD_AND_DRINK", "GENERAL_SERVICES", "ENTERTAINMENT", "LOAN_PAYMENTS",
                                        "PERSONAL_CARE", "TRANSFER_OUT", "TRANSFER_IN", "BANK_FEES", "MEDICAL",
                                        "TRAVEL", "INCOME"].sorted { $0.count > $1.count }

    private static func sentenceCased(_ raw: String) -> String {
        let words = raw.split(whereSeparator: { $0 == "_" || $0 == " " }).map { $0.lowercased() }
        guard let first = words.first else { return raw }
        let rest = words.dropFirst().map { $0 == "and" ? "&" : $0 }.joined(separator: " ")
        let head = first.prefix(1).uppercased() + first.dropFirst()
        return rest.isEmpty ? head : "\(head) \(rest)"
    }
}

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Expense"
    case income = "Income"
    var id: String { rawValue }
}

enum TransactionSource: String, Codable { case manual = "Manual", receipt = "Receipt", csv = "Spreadsheet", sample = "Sample", plaid = "Bank" }

/// What one card pays back in one category, for as long as it pays it. A rate without a window is
/// the card's standing offer; a rate with one is a promotion that will stop being true.
struct RewardRate: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Nil means everything the other rates do not cover.
    var category: SpendingCategory?
    /// 300 is 3% or 3x. Points are counted at a cent each until the user says otherwise.
    var basisPoints: Int
    var startsOn: Date?
    var endsOn: Date?
    var capCents: Int?
    var needsActivation: Bool = false
    var note: String = ""

    func applies(on date: Date) -> Bool {
        if let startsOn, date < startsOn { return false }
        if let endsOn, date > endsOn { return false }
        return true
    }
    var percentText: String {
        basisPoints % 100 == 0 ? "\(basisPoints / 100)%" : String(format: "%.1f%%", Double(basisPoints) / 100)
    }
}

struct BankAccount: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var detail: String
    var symbol: String = "building.columns.fill"
    var openingBalance: Int = 0
    var colorIndex: Int = 0
    /// The card product as the issuer names it — "Blue Cash Everyday®" — which is what its earn
    /// rates can be looked up against. The bank reports it; `name` stays whatever the user calls it.
    var officialName: String?
    var mask: String?
    var isCreditCard: Bool?
    /// Optional, not a defaulted array: a non-optional property fails to decode from a save written
    /// before it existed, however sensible its default looks.
    var rewards: [RewardRate]?
    /// The bank this account mirrors. Nil means it is kept by hand — cash, or anything not synced.
    /// A sync files each institution into its own account, so this is how one is found again.
    var institution: String?
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
    /// Plaid's transaction id, so a later sync can enrich or remove the row it already sent.
    var externalID: String?
    /// The bank's own detailed category, kept verbatim — the second level of the bucketing.
    var detailedCategory: String?
    /// Set when the user picks a category by hand. Without it there is no way to tell their choice
    /// from an earlier machine guess, and a sync would quietly overwrite both.
    var categoryPinned: Bool?
    /// Moves money rather than spending it; excluded from spending and income totals.
    /// Optional because a non-optional Bool would fail to decode every save written before it
    /// existed. Absent means the same as false: nothing was ever flagged as a transfer.
    var isTransfer: Bool?
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
    /// v4 gave every bank its own account, replacing the single catch-all the sync filed into.
    static let currentSchemaVersion = 4

    var schemaVersion: Int = currentSchemaVersion
    var name: String = "friend"
    var accounts: [BankAccount] = []
    var transactions: [Transaction] = []
    var isDemo: Bool = false

    /// Cash is the home for anything entered by hand. Synced banks add their own accounts.
    static func cashAccount() -> BankAccount {
        BankAccount(name: "Cash", detail: "Entered by hand", symbol: "banknote.fill")
    }

    static func empty() -> Self {
        FinanceData(accounts: [cashAccount()])
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
