import XCTest
import UIKit
@testable import Samgloyim

final class FinanceTests: XCTestCase {
    func testMoneyUsesExactCentsAndRejectsInvalidValues() {
        XCTAssertEqual(Money.parse("$1,234.56"), 123456)
        XCTAssertEqual(Money.parse("0.29"), 29)
        XCTAssertEqual(Money.parse("-10.50"), -1050)
        XCTAssertNil(Money.parse("12.345"))
        XCTAssertNil(Money.parse("NaN"))
        XCTAssertNil(Money.parse("1e8"))
        XCTAssertNil(Money.parse("1,2"))
        XCTAssertNil(Money.parse("$$12"))
        XCTAssertNil(Money.parse("999999999999999999"))
        XCTAssertNil(Money.parse(""))
    }

    func testDuplicateCandidatesAreAccountAndDaySpecific() throws {
        let account = UUID()
        let date = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        let first = Transaction(merchant: "Corner Café!", amount: 450, date: date, category: .food, accountID: account)
        var second = Transaction(merchant: "corner cafe", amount: 450, date: date, category: .food, accountID: account, source: .receipt)
        XCTAssertTrue(DuplicateDetector.matches(first, second))
        second.accountID = UUID()
        XCTAssertFalse(DuplicateDetector.matches(first, second))
        second.accountID = account
        second.date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        XCTAssertFalse(DuplicateDetector.matches(first, second))
        second.date = date; second.kind = .income
        XCTAssertFalse(DuplicateDetector.matches(first, second))
        XCTAssertFalse(DuplicateDetector.matches(first, first))
    }

    func testCSVHandlesQuotesNewlinesAndByteOrderMark() throws {
        let account = BankAccount(name: "Everyday", detail: "Checking")
        let csv = "\u{FEFF}date,merchant,amount,kind,note\r\n2026-09-18,\"Coffee, \"\"and\"\" Co\",\"1,234.56\",expense,\"line one\nline two\"\r\n"
        let result = try CSVService.parse(csv, accounts: [account], defaultAccountID: account.id)
        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions.first?.merchant, "Coffee, \"and\" Co")
        XCTAssertEqual(result.transactions.first?.amount, 123456)
        XCTAssertEqual(result.transactions.first?.note, "line one\nline two")
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testCSVReportsMalformedRowsInsteadOfInventingValues() throws {
        let account = BankAccount(name: "Everyday", detail: "Checking")
        let csv = "date,merchant,amount,account,kind\n2026-02-30,No date,5,Everyday,expense\n2026-09-18,Bad amount,abc,Everyday,expense\n2026-09-18,Wrong account,5,Missing,expense\n2026-09-18,Wrong kind,5,Everyday,transfer\n2026-09-18,Campus job,500,Everyday,income"
        let result = try CSVService.parse(csv, accounts: [account], defaultAccountID: account.id)
        XCTAssertEqual(result.warnings.count, 4)
        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions[0].kind, .income)
        XCTAssertEqual(result.transactions[0].amount, 50000)
    }

    func testCSVRequiresUnambiguousHeadersAndQuotes() {
        let account = BankAccount(name: "Test", detail: "")
        XCTAssertThrowsError(try CSVService.parse("date,amount\n2026-09-18,5", accounts: [account], defaultAccountID: account.id))
        XCTAssertThrowsError(try CSVService.parse("date,merchant,amount,amount\n2026-09-18,X,5,5", accounts: [account], defaultAccountID: account.id))
        XCTAssertThrowsError(try CSVService.rows("date,merchant\n2026-09-18,\"unfinished"))
        XCTAssertThrowsError(try CSVService.rows("\"hello\"oops,test"))
    }

    func testCSVExportRoundTripsAmountsKindsAndNotes() throws {
        let account = BankAccount(name: "Everyday", detail: "")
        let transaction = Transaction(merchant: "Trader Joe’s", amount: 2057, date: Date(), category: .groceries, accountID: account.id, kind: .income, note: "a, b\nsecond line")
        let result = try CSVService.parse(CSVService.export([transaction], accounts: [account]), accounts: [account], defaultAccountID: account.id)
        XCTAssertEqual(result.transactions[0].amount, 2057)
        XCTAssertEqual(result.transactions[0].kind, .income)
        XCTAssertEqual(result.transactions[0].note, transaction.note)
        XCTAssertEqual(result.transactions[0].category, .groceries)
    }

    func testCSVExportNeutralizesFormulaLikeMerchantNames() {
        let account = BankAccount(name: "Test", detail: "")
        let transaction = Transaction(merchant: "=SUM(1,2)", amount: 100, date: Date(), category: .other, accountID: account.id)
        XCTAssertTrue(CSVService.export([transaction], accounts: [account]).contains("'=SUM(1,2)"))
    }

    func testReceiptParserPrefersTotalOverSubtotalTaxAndChange() {
        let reading = ReceiptScanner.parse(lines: ["CAMPUS CAFE", "09/18/2026", "SUBTOTAL 14.00", "TAX 1.12", "TOTAL $15.12", "CASH 20.00", "CHANGE 4.88"])
        XCTAssertEqual(reading.merchant, "CAMPUS CAFE")
        XCTAssertEqual(reading.amount, 1512)
        XCTAssertNotNil(reading.date)
    }

    func testReceiptWithoutTotalRequiresManualReview() {
        let reading = ReceiptScanner.parse(lines: ["COFFEE SHOP", "Latte 5.00", "SUBTOTAL 5.00", "TAX 0.50"])
        XCTAssertNil(reading.amount)
        XCTAssertEqual(ReceiptScanner.parse(lines: ["STORE", "TOTAL", "1234.56"]).amount, 123456)
        XCTAssertEqual(ReceiptScanner.parse(lines: ["STORE", "BALANCE DUE 15.00"]).amount, 1500)
    }

    func testSyncedBankDatesLandOnTheLocalCalendarDay() throws {
        let payload = PlaidTransactionPayload(id: "t1", merchant: "Trader Joe's", amountCents: 6842, kind: "expense",
                                              date: "2026-09-18", category: "GROCERIES", institution: "Test Bank", pending: false)
        let transaction = payload.toTransaction(accountID: UUID())
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: transaction.date)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 9)
        // Parsing as UTC would land this on the 17th at 8 PM for anyone west of London.
        XCTAssertEqual(parts.day, 18)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertNil(transaction.recordedTime, "A bank row has no clock time to show")
    }

    func testManualEntriesKeepTheirTimeAndImportedOnesDoNot() throws {
        let account = UUID()
        let day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        XCTAssertNil(Transaction(merchant: "CSV row", amount: 500, date: day, category: .food, accountID: account).recordedTime)
        let afternoon = try XCTUnwrap(Calendar.current.date(bySettingHour: 14, minute: 41, second: 0, of: day))
        XCTAssertNotNil(Transaction(merchant: "Manual", amount: 500, date: afternoon, category: .food, accountID: account).recordedTime)
    }

    func testReceiptMatchesCardPurchaseOnExactTotal() throws {
        let account = UUID()
        let day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        let purchase = Transaction(merchant: "Campus Cafe", amount: 1512, date: day, category: .food, accountID: account, source: .plaid)
        let other = Transaction(merchant: "Metro pass", amount: 340, date: day, category: .transport, accountID: account, source: .plaid)
        let reading = ReceiptReading(merchant: "CAMPUS CAFE #204", amount: 1512, date: day, text: "")
        let matches = ReceiptMatcher.matches(for: reading, in: [purchase, other], now: day)
        XCTAssertEqual(matches.map(\.id), [purchase.id])
        XCTAssertEqual(ReceiptMatcher.suggestion(from: matches)?.id, purchase.id)
    }

    func testReceiptTotalMatchingNoPurchaseIsNeverApproximated() throws {
        let account = UUID()
        let day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        let purchase = Transaction(merchant: "Campus Cafe", amount: 1512, date: day, category: .food, accountID: account)
        // A cent apart is a different purchase, not a near miss to round onto.
        XCTAssertTrue(ReceiptMatcher.matches(for: ReceiptReading(merchant: "CAMPUS CAFE", amount: 1513, date: day, text: ""), in: [purchase], now: day).isEmpty)
        XCTAssertTrue(ReceiptMatcher.matches(for: ReceiptReading(merchant: "CAMPUS CAFE", amount: nil, date: day, text: ""), in: [purchase], now: day).isEmpty)
    }

    func testEquallyGoodPurchasesAreLeftForTheUserToMap() throws {
        let account = UUID()
        let day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        let first = Transaction(merchant: "Corner Store", amount: 900, date: day, category: .shopping, accountID: account)
        let second = Transaction(merchant: "Corner Store", amount: 900, date: day, category: .shopping, accountID: account)
        let matches = ReceiptMatcher.matches(for: ReceiptReading(merchant: "Corner Store", amount: 900, date: day, text: ""), in: [first, second], now: day)
        XCTAssertEqual(matches.count, 2)
        XCTAssertNil(ReceiptMatcher.suggestion(from: matches))
    }

    func testMatchingSkipsIncomeAlreadyReceiptedAndDistantPurchases() throws {
        let account = UUID()
        let day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        let reading = ReceiptReading(merchant: "Campus Cafe", amount: 1512, date: day, text: "")
        var receipted = Transaction(merchant: "Campus Cafe", amount: 1512, date: day, category: .food, accountID: account)
        receipted.receipt = ReceiptAttachment(merchant: "Campus Cafe", total: 1512, purchasedAt: day, text: "")
        let income = Transaction(merchant: "Campus Cafe", amount: 1512, date: day, category: .food, accountID: account, kind: .income)
        let distant = Transaction(merchant: "Campus Cafe", amount: 1512, date: try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -9, to: day)), category: .food, accountID: account)
        XCTAssertTrue(ReceiptMatcher.matches(for: reading, in: [receipted, income, distant], now: day).isEmpty)
    }

    func testPostingLagStillMatchesButWeakensTheSuggestion() throws {
        let account = UUID()
        let day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        let posted = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 3, to: day))
        let purchase = Transaction(merchant: "Trader Joe's", amount: 6842, date: posted, category: .groceries, accountID: account, source: .plaid)
        let named = ReceiptMatcher.matches(for: ReceiptReading(merchant: "TRADER JOES", amount: 6842, date: day, text: ""), in: [purchase], now: day)
        XCTAssertEqual(ReceiptMatcher.suggestion(from: named)?.id, purchase.id)
        // Same lag without a recognizable merchant is a match worth showing, but not one to suggest.
        let anonymous = ReceiptMatcher.matches(for: ReceiptReading(merchant: "Receipt", amount: 6842, date: day, text: ""), in: [purchase], now: day)
        XCTAssertEqual(anonymous.count, 1)
        XCTAssertNil(ReceiptMatcher.suggestion(from: anonymous))
    }

    @MainActor func testAttachingReceiptPersistsAndClearsTheCandidate() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FinanceStore(fileURL: url, demo: false)
        let account = try XCTUnwrap(store.data.accounts.first)
        let purchase = Transaction(merchant: "Campus Cafe", amount: 1512, date: Date(), category: .food, accountID: account.id, source: .plaid)
        XCTAssertTrue(store.save(purchase))
        XCTAssertEqual(store.receiptCandidates.map(\.id), [purchase.id])
        let receipt = ReceiptAttachment(merchant: "CAMPUS CAFE", total: 1512, purchasedAt: Date(), text: "TOTAL 15.12", mappedManually: true)
        XCTAssertTrue(store.attachReceipt(receipt, to: purchase.id))
        XCTAssertTrue(store.receiptCandidates.isEmpty)
        XCTAssertFalse(store.attachReceipt(receipt, to: UUID()))

        let reloaded = FinanceStore(fileURL: url, demo: false)
        XCTAssertEqual(reloaded.data.transactions.first?.receipt?.total, 1512)
        XCTAssertEqual(reloaded.data.transactions.first?.receipt?.mappedManually, true)
        XCTAssertTrue(reloaded.removeReceipt(from: purchase.id))
        XCTAssertNil(reloaded.data.transactions.first?.receipt)
    }

    @MainActor func testSavesFromBeforeReceiptsStillLoad() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let accountID = UUID(), transactionID = UUID()
        let legacy = """
        {"schemaVersion":1,"name":"friend","isDemo":false,"budgets":[],"goals":[],\
        "accounts":[{"id":"\(accountID.uuidString)","name":"Everyday","detail":"Checking","symbol":"building.columns.fill","openingBalance":0,"colorIndex":0}],\
        "transactions":[{"id":"\(transactionID.uuidString)","merchant":"Campus Cafe","amount":1512,"date":780000000,"category":"Food & drink",\
        "accountID":"\(accountID.uuidString)","kind":"Expense","source":"Bank","note":""}]}
        """
        try Data(legacy.utf8).write(to: url)
        let store = FinanceStore(fileURL: url, demo: false)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.data.schemaVersion, FinanceData.currentSchemaVersion)
        XCTAssertNil(store.data.transactions.first?.receipt)
        XCTAssertEqual(store.receiptCandidates.map(\.id), [transactionID])
    }

    @MainActor func testOnDeviceReceiptOCR() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 700)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 700))
            let font = UIFont.monospacedSystemFont(ofSize: 48, weight: .regular)
            for (index, line) in ["CAMPUS CAFE", "09/18/2026", "SUBTOTAL 14.00", "TAX 1.12", "TOTAL $15.12"].enumerated() {
                (line as NSString).draw(at: CGPoint(x: 55, y: 70 + index * 105), withAttributes: [.font: font, .foregroundColor: UIColor.black])
            }
        }
        let reading = try await ReceiptScanner.scan(XCTUnwrap(image.pngData()))
        XCTAssertTrue(reading.merchant.contains("CAMPUS"))
        XCTAssertEqual(reading.amount, 1512)
    }

    @MainActor func testPersistenceTotalsAndEditDelete() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FinanceStore(fileURL: url, demo: false)
        let account = try XCTUnwrap(store.data.accounts.first)
        var expense = Transaction(merchant: "Lunch", amount: 1200, date: Date(), category: .food, accountID: account.id)
        XCTAssertTrue(store.save(expense))
        XCTAssertTrue(store.save(Transaction(merchant: "Job", amount: 10000, date: Date(), category: .other, accountID: account.id, kind: .income)))
        XCTAssertEqual(store.spent, 1200)
        XCTAssertEqual(store.income, 10000)
        XCTAssertEqual(store.balance(account), 8800)
        expense.amount = 1500
        XCTAssertTrue(store.save(expense))
        XCTAssertEqual(store.data.transactions.count, 2)
        let restored = FinanceStore(fileURL: url, demo: false)
        XCTAssertEqual(restored.spent, 1500)
        XCTAssertTrue(restored.deleteTransaction(expense.id))
        XCTAssertEqual(FinanceStore(fileURL: url).data.transactions.count, 1)
    }

    @MainActor func testSpendingIsFilteredByAccountAndMonthAndExcludesIncome() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FinanceStore(fileURL: url, demo: false)
        let first = try XCTUnwrap(store.data.accounts.first)
        let second = BankAccount(name: "Cash", detail: "")
        XCTAssertTrue(store.saveAccount(second))
        XCTAssertTrue(store.add([Transaction(merchant: "A", amount: 1000, date: Date(), category: .food, accountID: first.id), Transaction(merchant: "B", amount: 2500, date: Date(), category: .food, accountID: second.id), Transaction(merchant: "Pay", amount: 50000, date: Date(), category: .other, accountID: first.id, kind: .income)]))
        store.selectedAccountID = first.id
        XCTAssertEqual(store.spent, 1000)
        XCTAssertEqual(store.income, 50000)
        store.selectedAccountID = nil
        XCTAssertEqual(store.spent, 3500)
        XCTAssertEqual(store.categoryTotals.first { $0.category == .food }?.amount, 3500)
        store.moveMonth(-1)
        XCTAssertEqual(store.spent, 0)
    }

    @MainActor func testResetClearsEverything() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FinanceStore(fileURL: url, demo: false)
        let account = try XCTUnwrap(store.data.accounts.first)
        XCTAssertTrue(store.save(Transaction(merchant: "Lunch", amount: 1200, date: Date(), category: .food, accountID: account.id)))
        XCTAssertEqual(store.data.transactions.count, 1)
        XCTAssertTrue(store.reset(useDemo: false))
        XCTAssertTrue(store.data.transactions.isEmpty)
        XCTAssertFalse(store.data.isDemo)
        XCTAssertEqual(store.data.accounts.count, 1)
    }

    @MainActor func testCorruptDataIsPreserved() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = Data("not valid JSON".utf8)
        try invalid.write(to: url)
        let store = FinanceStore(fileURL: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.reset(useDemo: true))
        XCTAssertEqual(try Data(contentsOf: url), invalid)
    }

    private func temporaryURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("finances.json") }
}
