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
    var expenses: [Transaction] { filteredTransactions.filter { $0.kind == .expense } }
    var spent: Int { expenses.reduce(0) { $0 + $1.amount } }
    var income: Int { filteredTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    var categoryTotals: [(category: SpendingCategory, amount: Int)] {
        SpendingCategory.allCases.map { category in (category, expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }
    func account(_ id: UUID) -> BankAccount? { data.accounts.first { $0.id == id } }
    func balance(_ account: BankAccount) -> Int {
        account.openingBalance + data.transactions.filter { $0.accountID == account.id }.reduce(0) { $0 + ($1.kind == .income ? $1.amount : -$1.amount) }
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
    @discardableResult func setName(_ name: String) -> Bool { update { $0.name = name.isEmpty ? "friend" : name } }
    @discardableResult func reset(useDemo: Bool) -> Bool {
        let result = update { $0 = useDemo ? .sample() : .empty() }
        if result { selectedAccountID = nil; selectedMonth = Date() }
        return result
    }
    func moveMonth(_ offset: Int) {
        selectedMonth = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) ?? selectedMonth
    }
    /// Silently pulls new transactions for any linked bank and merges them in, skipping known duplicates.
    /// Safe to call often (app launch, foreground) — a cursor-based sync only ever returns what's new.
    func autoSyncPlaid() async {
        guard let accountID = selectedAccountID ?? data.accounts.first?.id else { return }
        guard let items = try? await PlaidService.fetchLinkedItems(), !items.isEmpty else { return }
        guard let fetched = try? await PlaidService.fetchNewTransactions(accountID: accountID), !fetched.isEmpty else { return }
        var accepted: [Transaction] = []
        for candidate in fetched where duplicate(of: candidate, including: accepted) == nil {
            accepted.append(candidate)
        }
        if !accepted.isEmpty { add(accepted) }
    }
    func duplicate(of transaction: Transaction, including pending: [Transaction] = []) -> Transaction? {
        (data.transactions + pending).first { DuplicateDetector.matches($0, transaction) }
    }
}
