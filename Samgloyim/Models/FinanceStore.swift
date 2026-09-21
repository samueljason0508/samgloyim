import Foundation
import Combine

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var data: FinanceData
    @Published var selectedMonth = Date()
    @Published var selectedAccountID: UUID?
    @Published var errorMessage: String?
    private let fileURL: URL
    private var canWrite = true

    init(fileURL: URL? = nil, demo: Bool = true) {
        self.fileURL = fileURL ?? Self.defaultURL
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                var decoded = try JSONDecoder().decode(FinanceData.self, from: Data(contentsOf: self.fileURL))
                guard decoded.schemaVersion <= FinanceData.currentSchemaVersion else { throw CocoaError(.fileReadCorruptFile) }
                if decoded.schemaVersion < 3 { Self.repairSyncedDates(&decoded) }
                if decoded.schemaVersion < 4 { Self.splitAccountsByBank(&decoded) }
                decoded.schemaVersion = FinanceData.currentSchemaVersion
                data = decoded
            } else {
                data = demo ? .sample() : .empty()
            }
        } catch {
            data = .empty()
            canWrite = false
            errorMessage = "Your saved data couldn’t be read. The original file has been preserved. Restart the app or restore it from a backup before making changes."
        }
    }

    /// Bank rows synced before the timezone fix were parsed as UTC, so they sit at UTC midnight —
    /// the previous evening in any zone west of London. Sitting exactly on UTC midnight is the
    /// signature of that bug; a correctly parsed row sits on *local* midnight instead. Rebuild the
    /// affected rows on the calendar day the bank actually reported.
    static func repairSyncedDates(_ data: inout FinanceData) {
        var utc = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "UTC") else { return }
        utc.timeZone = zone
        for index in data.transactions.indices where data.transactions[index].source == .plaid {
            let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: data.transactions[index].date)
            guard parts.hour == 0, parts.minute == 0, parts.second == 0,
                  let corrected = Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
            else { continue }
            data.transactions[index].date = corrected
        }
    }

    /// Every synced row used to be filed into whichever single account the import picker happened
    /// to name, so four banks collapsed into one. Give each bank its own account and move its rows
    /// there. A hand-kept account is left alone; the leftover catch-all is dropped only when it has
    /// nothing in it and no opening balance to lose.
    static func splitAccountsByBank(_ data: inout FinanceData) {
        let before = Set(data.accounts.map(\.id))
        for index in data.transactions.indices {
            guard let institution = data.transactions[index].institutionName else { continue }
            data.transactions[index].accountID = accountID(forInstitution: institution, in: &data)
        }
        data.accounts.removeAll { account in
            before.contains(account.id) && Self.isOldDefault(account) && account.openingBalance == 0
                && !data.transactions.contains { $0.accountID == account.id }
        }
        // One the user typed into is not thrown away. It was never named by them either — it is the
        // account the app opened on their behalf — so it becomes Cash and keeps what it holds.
        for index in data.accounts.indices where Self.isOldDefault(data.accounts[index]) {
            let cash = FinanceData.cashAccount()
            data.accounts[index].name = cash.name
            data.accounts[index].detail = cash.detail
            data.accounts[index].symbol = cash.symbol
        }
        if !data.accounts.contains(where: { $0.institution == nil }) { data.accounts.append(FinanceData.cashAccount()) }
    }

    /// The catch-all the app used to open on a fresh start, matched exactly so an account the user
    /// named themselves is never renamed out from under them.
    private static func isOldDefault(_ account: BankAccount) -> Bool {
        account.institution == nil && account.name == "Everyday" && account.detail == "Personal account"
    }

    /// The account mirroring one bank, opened on first sight of it.
    static func accountID(forInstitution institution: String, in data: inout FinanceData) -> UUID {
        if let existing = data.accounts.first(where: { $0.institution == institution }) { return existing.id }
        let account = BankAccount(name: institution, detail: "Synced", colorIndex: data.accounts.count, institution: institution)
        data.accounts.append(account)
        return account.id
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Samgloyim", isDirectory: true).appendingPathComponent("finances.json")
    }

    var filteredTransactions: [Transaction] {
        transactions(in: selectedMonth, accountID: selectedAccountID)
    }
    func transactions(in month: Date, accountID: UUID? = nil) -> [Transaction] {
        data.transactions.filter {
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
                && (accountID == nil || $0.accountID == accountID)
        }.sorted { $0.date > $1.date }
    }
    /// Anything entered by hand belongs to Cash, not to a bank that never reported it.
    var cashAccountID: UUID? { (data.accounts.first { $0.institution == nil } ?? data.accounts.first)?.id }
    var expenses: [Transaction] { filteredTransactions.filter { $0.kind == .expense && $0.isTransfer != true } }
    var spent: Int { expenses.reduce(0) { $0 + $1.amount } }
    var income: Int { filteredTransactions.filter { $0.kind == .income && $0.isTransfer != true }.reduce(0) { $0 + $1.amount } }
    var transfers: [Transaction] { filteredTransactions.filter { $0.isTransfer == true } }
    var categoryTotals: [(category: SpendingCategory, amount: Int)] {
        SpendingCategory.allCases.map { category in (category, expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }
    func account(_ id: UUID) -> BankAccount? { data.accounts.first { $0.id == id } }
    func balance(_ account: BankAccount) -> Int {
        account.openingBalance + data.transactions.filter { $0.accountID == account.id }.reduce(0) { $0 + ($1.kind == .income ? $1.amount : -$1.amount) }
    }

    /// What the cards owe and what the accounts hold, across every account at once.
    ///
    /// Six accounts make the one number a person actually wants — am I ahead or behind — the one
    /// number nowhere on screen. `balance` runs negative on a card as it is spent, so what is owed
    /// is that balance turned around; a card in credit owes nothing rather than owing a negative.
    struct Standing {
        var owed: Int = 0
        var held: Int = 0
        var cards: [(account: BankAccount, owed: Int)] = []
        var net: Int { held - owed }
    }

    var standing: Standing {
        var result = Standing()
        for account in data.accounts {
            let balance = balance(account)
            if account.isCreditCard == true {
                let owed = max(0, -balance)
                result.owed += owed
                result.cards.append((account, owed))
            } else {
                result.held += balance
            }
        }
        result.cards.sort { $0.owed > $1.owed }
        return result
    }

    /// Spending by month, newest last, for the whole ledger or one category of it.
    ///
    /// Every other total in the app is one month wide, which answers "what did I spend" and never
    /// "is this getting worse". Transfers are excluded the way `expenses` excludes them: a card
    /// payoff is not eating out twice.
    func monthlyTotals(category: SpendingCategory? = nil, accountID: UUID? = nil, months: Int = 6, now: Date = Date()) -> [(month: Date, amount: Int)] {
        let calendar = Calendar.current
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return (0..<max(1, months)).reversed().compactMap { back in
            guard let month = calendar.date(byAdding: .month, value: -back, to: thisMonth) else { return nil }
            let total = transactions(in: month, accountID: accountID)
                .filter { $0.kind == .expense && $0.isTransfer != true && (category == nil || $0.category == category) }
                .reduce(0) { $0 + $1.amount }
            return (month, total)
        }
    }

    /// The categories worth charting: the ones with the most spend over the window, not the ones
    /// that happen to be busy this month.
    func trendingCategories(months: Int = 6, now: Date = Date(), limit: Int = 6) -> [SpendingCategory] {
        SpendingCategory.allCases
            .map { ($0, monthlyTotals(category: $0, months: months, now: now).reduce(0) { $0 + $1.amount }) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// The other half of a card payoff: the account the money left, or the card it landed on.
    ///
    /// A payoff arrives as two rows from two banks that have never heard of each other — money out
    /// of chequing, money onto the card — and both are already kept out of spending. Read alone
    /// each is a mystery row. The pairing is worked out when it is needed rather than stored:
    /// nothing to migrate, and a sync that corrects an amount re-pairs it for free.
    ///
    /// Two candidates are treated as none, the same rule receipt matching uses: a wrong pair
    /// claimed confidently is worse than no pair at all.
    func payoffPair(for transaction: Transaction, within days: Int = 3) -> Transaction? {
        guard transaction.isTransfer == true else { return nil }
        let calendar = Calendar.current
        let matches = data.transactions.filter { other in
            other.id != transaction.id
                && other.isTransfer == true
                && other.amount == transaction.amount
                && other.kind != transaction.kind
                && other.accountID != transaction.accountID
                && abs(calendar.dateComponents([.day], from: other.date, to: transaction.date).day ?? .max) <= days
        }
        return matches.count == 1 ? matches.first : nil
    }

    @discardableResult
    private func update(_ mutation: (inout FinanceData) -> Void) -> Bool {
        guard canWrite else {
            errorMessage = "Changes are unavailable because the original saved data could not be read. It has not been overwritten."
            return false
        }
        var updated = data
        mutation(&updated)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(updated)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            data = updated
            return true
        } catch {
            errorMessage = "Couldn’t save this change. Please check available storage and try again."
            return false
        }
    }

    @discardableResult func save(_ transaction: Transaction) -> Bool {
        guard transaction.amount > 0, transaction.amount <= Money.maximumCents,
              !transaction.merchant.trimmingCharacters(in: .whitespaces).isEmpty,
              account(transaction.accountID) != nil else { return false }
        return update { data in
            if let index = data.transactions.firstIndex(where: { $0.id == transaction.id }) { data.transactions[index] = transaction }
            else { data.transactions.append(transaction) }
        }
    }
    @discardableResult func add(_ transactions: [Transaction]) -> Bool {
        guard transactions.allSatisfy({ $0.amount > 0 && $0.amount <= Money.maximumCents && account($0.accountID) != nil }) else { return false }
        return update { $0.transactions.append(contentsOf: transactions) }
    }
    @discardableResult func deleteTransaction(_ id: UUID) -> Bool { update { $0.transactions.removeAll { $0.id == id } } }
    /// Card purchases a scanned receipt can still be mapped to, newest first.
    var receiptCandidates: [Transaction] {
        ReceiptMatcher.candidates(in: data.transactions).sorted { $0.date > $1.date }
    }
    @discardableResult func attachReceipt(_ receipt: ReceiptAttachment, to id: UUID) -> Bool {
        guard data.transactions.contains(where: { $0.id == id }) else { return false }
        return update { data in
            guard let index = data.transactions.firstIndex(where: { $0.id == id }) else { return }
            data.transactions[index].receipt = receipt
        }
    }
    @discardableResult func removeReceipt(from id: UUID) -> Bool {
        update { data in
            guard let index = data.transactions.firstIndex(where: { $0.id == id }) else { return }
            data.transactions[index].receipt = nil
        }
    }
    @discardableResult func saveAccount(_ account: BankAccount) -> Bool {
        update { data in
            if let index = data.accounts.firstIndex(where: { $0.id == account.id }) { data.accounts[index] = account }
            else { data.accounts.append(account) }
        }
    }
    /// Folds one account into another, transactions and all.
    ///
    /// A bank reported under two names — an old link and a new one, or the same card seen twice —
    /// leaves every per-account total and the account filter quietly wrong, and there is no way
    /// back from inside the app. The target keeps its own name, rates and identity: it is the one
    /// the user chose to keep. Opening balances add, because both were real money.
    @discardableResult func mergeAccount(_ source: UUID, into target: UUID) -> Bool {
        guard source != target, account(source) != nil, account(target) != nil else { return false }
        let result = update { data in
            guard let sourceIndex = data.accounts.firstIndex(where: { $0.id == source }),
                  let targetIndex = data.accounts.firstIndex(where: { $0.id == target }) else { return }
            let absorbed = data.accounts[sourceIndex]
            for index in data.transactions.indices where data.transactions[index].accountID == source {
                data.transactions[index].accountID = target
            }
            data.accounts[targetIndex].openingBalance += absorbed.openingBalance
            // Rates only exist where someone looked them up; an empty target should inherit rather
            // than lose them, and a target that has its own keeps them.
            if (data.accounts[targetIndex].rewards ?? []).isEmpty, let inherited = absorbed.rewards, !inherited.isEmpty {
                data.accounts[targetIndex].rewards = inherited
            }
            if data.accounts[targetIndex].officialName == nil { data.accounts[targetIndex].officialName = absorbed.officialName }
            if data.accounts[targetIndex].mask == nil { data.accounts[targetIndex].mask = absorbed.mask }
            if data.accounts[targetIndex].isCreditCard == nil { data.accounts[targetIndex].isCreditCard = absorbed.isCreditCard }
            // The institution is how a sync finds this account again. Keeping the absorbed one
            // when the target has none is what stops the next sync reopening what was just merged.
            if data.accounts[targetIndex].institution == nil { data.accounts[targetIndex].institution = absorbed.institution }
            data.accounts.remove(at: sourceIndex)
        }
        // Filtering by an account that no longer exists shows an empty month, not an error.
        if result, selectedAccountID == source { selectedAccountID = target }
        return result
    }

    @discardableResult func setName(_ name: String) -> Bool { update { $0.name = name.isEmpty ? "friend" : name } }
    @discardableResult func reset(useDemo: Bool) -> Bool {
        let result = update { $0 = useDemo ? .sample() : .empty() }
        if result { selectedAccountID = nil; selectedMonth = Date() }
        return result
    }
    func moveMonth(_ offset: Int) {
        selectedMonth = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) ?? selectedMonth
    }
    /// Silently pulls changes for any linked bank and merges them in.
    /// Safe to call often (app launch, foreground) — a cursor-based sync only returns what changed.
    func autoSyncPlaid() async {
        guard let items = try? await PlaidService.fetchLinkedItems(), !items.isEmpty else { return }
        guard let sync = try? await PlaidService.fetchSync() else { return }
        apply(sync)
    }

    /// Merges one sync into the ledger.
    ///
    /// A bank first reports a purchase while it is pending, before it knows the merchant or what
    /// the spending was for, then re-reports it enriched once it posts. Applying only `added`
    /// leaves those rows stuck with the raw card descriptor and no category forever, which is how
    /// almost everything ends up filed under Other.
    /// `addNew` is false when the caller is putting new rows in front of the user for review;
    /// corrections and reversals still apply, because a cursor only reports them once.
    @discardableResult func apply(_ sync: PlaidSync, addNew: Bool = true) -> Bool {
        var changed = false
        let result = update { data in
            for payload in sync.accounts {
                let index = data.accounts.firstIndex { $0.id == Self.accountID(forInstitution: payload.institution, in: &data) }
                guard let index else { continue }
                // The bank describes the card; the user owns what they call it and what it earns.
                if data.accounts[index].officialName != payload.officialName
                    || data.accounts[index].isCreditCard != payload.isCreditCard {
                    data.accounts[index].officialName = payload.officialName
                    data.accounts[index].mask = payload.mask
                    data.accounts[index].isCreditCard = payload.isCreditCard
                    if payload.isCreditCard { data.accounts[index].symbol = "creditcard.fill" }
                    changed = true
                }
            }
            for id in sync.removed where data.transactions.contains(where: { $0.externalID == id }) {
                data.transactions.removeAll { $0.externalID == id }
                changed = true
            }
            for payload in sync.added + sync.modified {
                let incoming = payload.toTransaction(accountID: Self.accountID(forInstitution: payload.institution, in: &data))
                if let index = Self.index(of: incoming, in: data.transactions) {
                    var existing = data.transactions[index]
                    // The bank owns these.
                    existing.merchant = incoming.merchant
                    existing.amount = incoming.amount
                    existing.date = incoming.date
                    existing.kind = incoming.kind
                    existing.isTransfer = incoming.isTransfer
                    existing.note = incoming.note
                    existing.externalID = incoming.externalID
                    existing.accountID = incoming.accountID
                    existing.detailedCategory = incoming.detailedCategory
                    // A category the user picked by hand is theirs. Anything else is a machine
                    // guess, and a later sync — or a better mapping — is entitled to redo it.
                    if existing.categoryPinned != true { existing.category = incoming.category }
                    guard existing != data.transactions[index] else { continue }
                    data.transactions[index] = existing
                    changed = true
                } else if addNew, (data.transactions.first { DuplicateDetector.matches($0, incoming) }) == nil {
                    data.transactions.append(incoming)
                    changed = true
                }
            }
        }
        return result && changed
    }

    /// The row a synced transaction belongs to. Matching on the bank's own id is exact. Rows synced
    /// before ids were stored carry none, so those fall back to amount, day and account — but not
    /// merchant, because the row most in need of repair is precisely the one the bank has since
    /// renamed from a card descriptor to a real merchant. Two bank rows alike in amount and day can
    /// be claimed in either order; both are rewritten from the bank's own data, so the ledger ends
    /// up the same either way. Only bank rows are ever adopted — a manual entry that happens to
    /// look identical stays the user's.
    private static func index(of incoming: Transaction, in transactions: [Transaction]) -> Int? {
        if let id = incoming.externalID,
           let index = transactions.firstIndex(where: { $0.externalID == id }) { return index }
        return transactions.firstIndex {
            $0.source == .plaid && $0.externalID == nil && $0.amount == incoming.amount
                && $0.kind == incoming.kind && $0.institutionName == incoming.institutionName
                && Calendar.current.isDate($0.date, inSameDayAs: incoming.date)
        }
    }
    /// Turns freshly synced rows into transactions for review, opening an account for any bank
    /// not seen before so the user is reviewing rows that already know where they belong.
    func resolve(_ payloads: [PlaidTransactionPayload]) -> [Transaction] {
        var resolved: [Transaction] = []
        update { data in
            resolved = payloads.map { $0.toTransaction(accountID: Self.accountID(forInstitution: $0.institution, in: &data)) }
        }
        return resolved
    }
    @discardableResult func setRewards(_ rewards: [RewardRate], for accountID: UUID) -> Bool {
        update { data in
            guard let index = data.accounts.firstIndex(where: { $0.id == accountID }) else { return }
            data.accounts[index].rewards = rewards
        }
    }

    /// Asks the backend what a card earns and files the answer against it. Failing is ordinary —
    /// the lookup needs a key the user may not have set — so the caller is told and the rates stay
    /// editable by hand.
    func lookUpRewards(for account: BankAccount) async throws {
        // The issuer matters: "Blue Cash Everyday®" alone is ambiguous, "American Express Blue Cash
        // Everyday®" is not, and a search is only as good as the name it is given.
        let product = account.officialName ?? account.name
        guard let card = account.institution.map({ "\($0) \(product)" }) ?? account.officialName else {
            throw ImportError.message("There's no card name to look up. Add one first.")
        }
        let rates = try await RewardsService.lookup(card: card)
        guard !rates.isEmpty else { throw ImportError.message("No published rates came back for that card. Enter them by hand.") }
        setRewards(rates, for: account.id)
    }

    /// Cards that could be used at a place like this, best first.
    func cards(for category: SpendingCategory, now: Date = Date()) -> [CardSuggestion] {
        CardAdvisor.rank(data.accounts, for: category, now: now)
    }
    func duplicate(of transaction: Transaction, including pending: [Transaction] = []) -> Transaction? {
        (data.transactions + pending).first { DuplicateDetector.matches($0, transaction) }
    }
}
