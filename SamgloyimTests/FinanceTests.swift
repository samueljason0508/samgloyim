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

    func testBankTimestampIsUsedOnlyWhenTheInstitutionSendsARealOne() throws {
        // Chime sends a real authorized_datetime; most institutions send null or a midnight placeholder.
        let real = try XCTUnwrap(PlaidService.timestamp(from: "2026-09-13T21:55:52Z"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.dateComponents([.hour, .minute], from: real).hour, 21)
        XCTAssertNil(PlaidService.timestamp(from: "2026-09-13T00:00:00Z"), "A midnight placeholder is not a time")
        XCTAssertNil(PlaidService.timestamp(from: nil))
        XCTAssertNil(PlaidService.timestamp(from: "not a date"))

        let timed = PlaidTransactionPayload(id: "t1", merchant: "Chime buy", amountCents: 1200, kind: "expense",
                                            date: "2026-09-13", datetime: "2026-09-13T21:55:52Z", category: nil,
                                            categoryDetailed: nil, institution: "Chime", pending: false).toTransaction(accountID: UUID())
        XCTAssertNotNil(timed.recordedTime, "A bank that sends a clock time should surface one")
        XCTAssertEqual(timed.date, real)
    }

    func testSyncedBankDatesLandOnTheLocalCalendarDay() throws {
        let payload = PlaidTransactionPayload(id: "t1", merchant: "Trader Joe's", amountCents: 6842, kind: "expense",
                                              date: "2026-09-18", datetime: nil, category: "GROCERIES",
                                              categoryDetailed: "GROCERIES_GROCERIES", institution: "Test Bank", pending: false)
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

    @MainActor func testMigrationRepairsBankRowsStoredADayEarly() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let account = UUID()
        let utcMidnight = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        let localMidnight = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 18)))

        var data = FinanceData(schemaVersion: 2, accounts: [BankAccount(id: account, name: "Everyday", detail: "")],
            transactions: [
                Transaction(merchant: "Bank row", amount: 6842, date: utcMidnight, category: .groceries, accountID: account, source: .plaid),
                Transaction(merchant: "Manual row", amount: 500, date: utcMidnight, category: .food, accountID: account, source: .manual)
            ])
        FinanceStore.repairSyncedDates(&data)

        XCTAssertEqual(data.transactions[0].date, localMidnight, "The bank row should land on the day the bank reported")
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: data.transactions[0].date).day, 18)
        XCTAssertEqual(data.transactions[1].date, utcMidnight, "Rows from other sources are never rewritten")

        // Running again must not shift the date a second time.
        var again = data
        FinanceStore.repairSyncedDates(&again)
        XCTAssertEqual(again.transactions[0].date, localMidnight)
    }

    func testDetailedPlaidCategoryIsPreferredOverTheCatchAllPrimaryOne() {
        // GENERAL_SERVICES covers tuition, insurance and car servicing alike, so reading only the
        // primary category files all three under Other.
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "GENERAL_SERVICES", detailed: "GENERAL_SERVICES_EDUCATION"), .education)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "GENERAL_SERVICES", detailed: "GENERAL_SERVICES_INSURANCE"), .services)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "GENERAL_SERVICES", detailed: "GENERAL_SERVICES_AUTOMOTIVE"), .transport)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "LOAN_PAYMENTS", detailed: "LOAN_PAYMENTS_STUDENT_LOAN_PAYMENT"), .education)
        // A detailed value we do not map falls back to the primary rather than guessing.
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "GROCERIES", detailed: "GROCERIES_SOMETHING_NEW"), .groceries)
        XCTAssertNil(SpendingCategory.fromPlaid(primary: nil, detailed: nil))
    }

    @MainActor func testMovingMoneyBetweenYourOwnAccountsIsNotSpending() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FinanceStore(fileURL: url, demo: false)
        let account = try XCTUnwrap(store.data.accounts.first)
        XCTAssertTrue(SpendingCategory.isTransfer(primary: "LOAN_PAYMENTS", detailed: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"))
        XCTAssertTrue(SpendingCategory.isTransfer(primary: "TRANSFER_OUT", detailed: "TRANSFER_OUT_ACCOUNT_TRANSFER"))
        XCTAssertTrue(SpendingCategory.isTransfer(primary: "TRANSFER_OUT", detailed: "TRANSFER_OUT_WITHDRAWAL"))
        XCTAssertTrue(SpendingCategory.isTransfer(primary: "TRANSFER_OUT", detailed: nil), "Nothing to tell a self-transfer apart on")
        XCTAssertFalse(SpendingCategory.isTransfer(primary: "FOOD_AND_DRINK", detailed: "FOOD_AND_DRINK_COFFEE"))

        // Zelle to a person is money spent, even though Plaid files it beside genuine transfers.
        XCTAssertFalse(SpendingCategory.isTransfer(primary: "TRANSFER_OUT", detailed: "TRANSFER_OUT_TRANSFER_OUT_FROM_APPS"))
        XCTAssertFalse(SpendingCategory.isTransfer(primary: "TRANSFER_OUT", detailed: "TRANSFER_OUT_OTHER_TRANSFER_OUT"))
        // Amex Send is person-to-person however Plaid files it, so the outgoing side is spending.
        XCTAssertFalse(SpendingCategory.isTransfer(primary: "TRANSFER_OUT", detailed: "TRANSFER_OUT_ACCOUNT_TRANSFER", merchant: "Amex Send: Add Money"))
        XCTAssertTrue(SpendingCategory.isTransfer(primary: "TRANSFER_OUT", detailed: "TRANSFER_OUT_ACCOUNT_TRANSFER", merchant: "External Withdrawal - HAPPEN BANK"))
        // Incoming stays out of income: a repayment, or the user's own money arriving, is not earnings.
        XCTAssertTrue(SpendingCategory.isTransfer(primary: "TRANSFER_IN", detailed: "TRANSFER_IN_TRANSFER_IN_FROM_APPS"))
        XCTAssertTrue(SpendingCategory.isTransfer(primary: "TRANSFER_IN", detailed: "TRANSFER_IN_OTHER_TRANSFER_IN"))

        var payment = Transaction(merchant: "Amex payment", amount: 120_000, date: Date(), category: .other, accountID: account.id, source: .plaid)
        payment.isTransfer = true
        let lunch = Transaction(merchant: "Campus Cafe", amount: 1200, date: Date(), category: .food, accountID: account.id, source: .plaid)
        XCTAssertTrue(store.add([payment, lunch]))
        // A card payoff would otherwise double-count purchases already recorded, and swamp the month.
        XCTAssertEqual(store.spent, 1200)
        XCTAssertEqual(store.transfers.count, 1)
        XCTAssertFalse(store.categoryTotals.contains { $0.category == .other })
    }

    @MainActor func testSyncEnrichesAPendingRowRatherThanFilingItUnderOtherForever() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FinanceStore(fileURL: url, demo: false)
        let raw = PlaidTransactionPayload(id: "plaid-1", merchant: "SQ *WB2 1042", amountCents: 1850, kind: "expense",
                                          date: "2026-09-18", datetime: nil, category: nil, categoryDetailed: nil,
                                          institution: "Amex", pending: true)
        XCTAssertTrue(store.apply(PlaidSync(added: [raw])))
        XCTAssertEqual(store.data.transactions.first?.category, .other)

        let posted = PlaidTransactionPayload(id: "plaid-1", merchant: "Whole Foods", amountCents: 1850, kind: "expense",
                                             date: "2026-09-18", datetime: nil, category: "GROCERIES",
                                             categoryDetailed: "GROCERIES_GROCERIES", institution: "Amex",
                                             pending: false)
        XCTAssertTrue(store.apply(PlaidSync(modified: [posted])))
        XCTAssertEqual(store.data.transactions.count, 1, "A correction must update the row, not add a second one")
        XCTAssertEqual(store.data.transactions.first?.merchant, "Whole Foods")
        XCTAssertEqual(store.data.transactions.first?.category, .groceries)
        XCTAssertEqual(store.data.transactions.first?.note, "Amex")
        // The bank got its own account on first sight, rather than landing in the cash one.
        let amex = try XCTUnwrap(store.data.accounts.first { $0.institution == "Amex" })
        XCTAssertEqual(store.data.transactions.first?.accountID, amex.id)
        XCTAssertNotEqual(amex.id, store.cashAccountID)

        // A category the user chose by hand is theirs, and a later sync must not overwrite it.
        var edited = try XCTUnwrap(store.data.transactions.first)
        edited.category = .fun
        edited.categoryPinned = true
        XCTAssertTrue(store.save(edited))
        XCTAssertFalse(store.apply(PlaidSync(modified: [posted])))
        XCTAssertEqual(store.data.transactions.first?.category, .fun)

        XCTAssertTrue(store.apply(PlaidSync(removed: ["plaid-1"])))
        XCTAssertTrue(store.data.transactions.isEmpty, "A transaction the bank reversed should not linger")
    }

    @MainActor func testResyncRepairsBankRowsStoredBeforeIdsWereKept() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FinanceStore(fileURL: url, demo: false)
        let account = try XCTUnwrap(store.data.accounts.first)
        let day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        let old = Transaction(merchant: "SQ *WB2 1042", amount: 1850, date: day, category: .other, accountID: account.id, source: .plaid, note: "Amex")
        let manual = Transaction(merchant: "SQ *WB2 1042", amount: 1850, date: day, category: .other, accountID: account.id, source: .manual)
        XCTAssertTrue(store.add([old, manual]))

        // The bank has since renamed the card descriptor, which is why merchant is not part of the match.
        let incoming = PlaidTransactionPayload(id: "plaid-1", merchant: "Whole Foods", amountCents: 1850, kind: "expense",
                                               date: "2026-09-18", datetime: nil, category: "GROCERIES",
                                               categoryDetailed: "GROCERIES_GROCERIES", institution: "Amex",
                                               pending: false)
        XCTAssertTrue(store.apply(PlaidSync(added: [incoming])))
        XCTAssertEqual(store.data.transactions.count, 2, "The replayed row should adopt the stored one, not duplicate it")
        let repaired = try XCTUnwrap(store.data.transactions.first { $0.source == .plaid })
        XCTAssertEqual(repaired.id, old.id)
        XCTAssertEqual(repaired.externalID, "plaid-1")
        XCTAssertEqual(repaired.category, .groceries)
        XCTAssertEqual(repaired.merchant, "Whole Foods")
        // The identical manual entry belongs to the user and is never claimed by a bank.
        let untouched = try XCTUnwrap(store.data.transactions.first { $0.source == .manual })
        XCTAssertNil(untouched.externalID)
        XCTAssertEqual(untouched.category, .other)
    }

    @MainActor func testMigrationGivesEachBankItsOwnAccount() throws {
        let catchAll = UUID(), day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        var data = FinanceData(schemaVersion: 3, accounts: [BankAccount(id: catchAll, name: "Everyday", detail: "Personal account")],
            transactions: [
                Transaction(merchant: "Bagel", amount: 500, date: day, category: .food, accountID: catchAll, source: .plaid, note: "Amex"),
                Transaction(merchant: "Coffee", amount: 400, date: day, category: .food, accountID: catchAll, source: .plaid, note: "Pending at Amex"),
                Transaction(merchant: "Bus", amount: 300, date: day, category: .transport, accountID: catchAll, source: .plaid, note: "Chime")
            ])
        FinanceStore.splitAccountsByBank(&data)

        let amex = try XCTUnwrap(data.accounts.first { $0.institution == "Amex" })
        let chime = try XCTUnwrap(data.accounts.first { $0.institution == "Chime" })
        XCTAssertEqual(data.transactions.filter { $0.accountID == amex.id }.count, 2, "Pending and posted rows belong to the same bank")
        XCTAssertEqual(data.transactions.filter { $0.accountID == chime.id }.count, 1)

        // Nothing is left in the catch-all, so it goes; hand-entered rows still need a home.
        XCTAssertFalse(data.accounts.contains { $0.id == catchAll })
        XCTAssertEqual(data.accounts.count, 3)
        XCTAssertEqual(data.accounts.first { $0.institution == nil }?.name, "Cash")
    }

    @MainActor func testMigrationTurnsTheOldCatchAllIntoCashWhenItStillHoldsSomething() throws {
        let catchAll = UUID(), day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        var data = FinanceData(schemaVersion: 3, accounts: [BankAccount(id: catchAll, name: "Everyday", detail: "Personal account")],
            transactions: [
                Transaction(merchant: "Bagel", amount: 500, date: day, category: .food, accountID: catchAll, source: .plaid, note: "Amex"),
                Transaction(merchant: "Coffee", amount: 500, date: day, category: .food, accountID: catchAll, source: .manual)
            ])
        FinanceStore.splitAccountsByBank(&data)
        let cash = try XCTUnwrap(data.accounts.first { $0.institution == nil })
        XCTAssertEqual(cash.id, catchAll, "Renamed in place, so the row typed into it is not orphaned")
        XCTAssertEqual(cash.name, "Cash")
        XCTAssertEqual(data.transactions.first { $0.source == .manual }?.accountID, catchAll)
        XCTAssertEqual(data.accounts.count, 2)
    }

    @MainActor func testMigrationKeepsAnAccountThatStillHoldsSomething() throws {
        let kept = UUID(), balance = UUID(), day = try XCTUnwrap(CSVService.parseDate("2026-09-18"))
        var data = FinanceData(schemaVersion: 3,
            accounts: [BankAccount(id: kept, name: "Wallet", detail: "In your pocket"),
                       BankAccount(id: balance, name: "Everyday", detail: "Checking", openingBalance: 185_000)],
            transactions: [
                Transaction(merchant: "Bagel", amount: 500, date: day, category: .food, accountID: kept, source: .plaid, note: "Amex"),
                Transaction(merchant: "Tip", amount: 200, date: day, category: .food, accountID: kept, source: .manual)
            ])
        FinanceStore.splitAccountsByBank(&data)
        // A hand-entered row is never reassigned to a bank it did not come from, so its account stays.
        XCTAssertTrue(data.accounts.contains { $0.id == kept })
        XCTAssertEqual(data.transactions.first { $0.source == .manual }?.accountID, kept)
        // An opening balance is the user's money; dropping the account would silently lose it.
        XCTAssertTrue(data.accounts.contains { $0.id == balance })
        XCTAssertFalse(data.accounts.contains { $0.name == "Cash" }, "An account kept by hand already serves that purpose")
    }

    private func card(_ name: String, _ rates: [RewardRate]) -> BankAccount {
        BankAccount(name: name, detail: "Synced", isCreditCard: true, rewards: rates, institution: name)
    }

    func testTheBestCardIsTheOneEarningMostInThatCategoryToday() throws {
        let july = try XCTUnwrap(CSVService.parseDate("2026-07-01"))
        let september = try XCTUnwrap(CSVService.parseDate("2026-09-30"))
        let october = try XCTUnwrap(CSVService.parseDate("2026-10-01"))
        let december = try XCTUnwrap(CSVService.parseDate("2026-12-31"))
        let rotating = card("Rotating", [
            RewardRate(category: .transport, basisPoints: 500, startsOn: july, endsOn: september, capCents: 150_000, needsActivation: true),
            RewardRate(category: .food, basisPoints: 500, startsOn: october, endsOn: december, capCents: 150_000, needsActivation: true),
            RewardRate(category: nil, basisPoints: 100)
        ])
        let everyday = card("Everyday", [
            RewardRate(category: .groceries, basisPoints: 300, capCents: 600_000),
            RewardRate(category: nil, basisPoints: 100)
        ])
        let wallet = [rotating, everyday]

        // In September the rotating card is on transport, so it wins at a gas station.
        let gas = CardAdvisor.rank(wallet, for: .transport, now: september)
        XCTAssertEqual(gas.first?.account.name, "Rotating")
        XCTAssertEqual(gas.first?.basisPoints, 500)
        XCTAssertTrue(gas.first?.caveats.contains { $0.contains("activating") } == true)
        XCTAssertTrue(gas.first?.caveats.contains { $0.contains("$1,500") } == true)

        // A restaurant in September is a tie on the base rate: the quarter has not turned over yet.
        let dinnerNow = CardAdvisor.rank(wallet, for: .food, now: september)
        XCTAssertEqual(dinnerNow.map(\.basisPoints), [100, 100])
        XCTAssertNil(CardAdvisor.headline(dinnerNow)?.runnerUp, "Nothing beats anything, so there is no runner-up to name")
        XCTAssertTrue(dinnerNow.first { $0.account.name == "Rotating" }?.caveats.contains { $0.contains("from Oct") } == true)

        // The same restaurant in October is 5%.
        XCTAssertEqual(CardAdvisor.rank(wallet, for: .food, now: october).first?.basisPoints, 500)
        // Groceries never rotate, so the everyday card wins whatever the month.
        XCTAssertEqual(CardAdvisor.rank(wallet, for: .groceries, now: october).first?.account.name, "Everyday")
    }

    func testARateThatHasRunOutIsSaidOutLoudRatherThanQuietlyDropped() throws {
        let july = try XCTUnwrap(CSVService.parseDate("2026-07-01"))
        let september = try XCTUnwrap(CSVService.parseDate("2026-09-30"))
        let october = try XCTUnwrap(CSVService.parseDate("2026-10-05"))
        let rotating = card("Rotating", [
            RewardRate(category: .transport, basisPoints: 500, startsOn: july, endsOn: september),
            RewardRate(category: nil, basisPoints: 100)
        ])
        let ranked = CardAdvisor.rank([rotating], for: .transport, now: october)
        XCTAssertEqual(ranked.first?.basisPoints, 100, "An expired rate does not apply")
        // The card was the right answer last week; saying nothing would leave the user believing it.
        XCTAssertTrue(ranked.first?.caveats.contains { $0.contains("ended") } == true)
    }

    func testOnlyCardsAreRankedAndOnlyWhenSomethingBeatsSomething() throws {
        var debit = BankAccount(name: "Chime", detail: "Synced", institution: "Chime")
        debit.isCreditCard = false
        debit.rewards = [RewardRate(category: nil, basisPoints: 900)]
        let cash = FinanceData.cashAccount()
        let plain = card("Plain", [RewardRate(category: nil, basisPoints: 100)])

        let ranked = CardAdvisor.rank([debit, cash, plain], for: .food)
        XCTAssertEqual(ranked.map(\.account.name), ["Plain"], "A debit account earns nothing to compare")
        XCTAssertNotNil(CardAdvisor.headline(ranked))
        // A card with no rates at all is not a recommendation.
        XCTAssertNil(CardAdvisor.headline(CardAdvisor.rank([card("Unknown", [])], for: .food)))
    }

    func testNearbyPlacesMapOntoCategoriesTheAppCanSpendIn() {
        XCTAssertEqual(PlaceFinder.category(for: .restaurant), .food)
        XCTAssertEqual(PlaceFinder.category(for: .cafe), .food)
        XCTAssertEqual(PlaceFinder.category(for: .foodMarket), .groceries)
        XCTAssertEqual(PlaceFinder.category(for: .gasStation), .transport)
        XCTAssertEqual(PlaceFinder.category(for: .pharmacy), .health)
        XCTAssertEqual(PlaceFinder.category(for: .store), .shopping)
        // Somewhere you cannot pay for anything is not a place to recommend a card for.
        XCTAssertNil(PlaceFinder.category(for: .park))
        XCTAssertNil(PlaceFinder.category(for: .fireStation))
    }

    @MainActor func testRatesSurviveEditingTheAccountTheyBelongTo() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FinanceStore(fileURL: url, demo: false)
        var amex = BankAccount(name: "American Express", detail: "Synced", institution: "American Express")
        amex.isCreditCard = true
        XCTAssertTrue(store.saveAccount(amex))
        XCTAssertTrue(store.setRewards([RewardRate(category: .groceries, basisPoints: 300)], for: amex.id))

        let reloaded = FinanceStore(fileURL: url, demo: false)
        let stored = try XCTUnwrap(reloaded.account(amex.id))
        XCTAssertEqual(stored.rewards?.first?.basisPoints, 300)
        XCTAssertEqual(stored.rewards?.first?.percentText, "3%")
        XCTAssertEqual(stored.institution, "American Express")
    }

    func testTracingTheChartSnapsToADayThatHappened() {
        let points: [(day: Int, amount: Double)] = [(0, 0), (1, 12.5), (2, 40), (5, 99.75)]
        // A finger between two readings takes the closer one, never a value in between.
        XCTAssertEqual(OverviewView.nearest(to: 1, in: points)?.amount, 12.5)
        XCTAssertEqual(OverviewView.nearest(to: 3, in: points)?.day, 2)
        XCTAssertEqual(OverviewView.nearest(to: 4, in: points)?.day, 5)
        // Dragging past either end holds at the end rather than losing the readout.
        XCTAssertEqual(OverviewView.nearest(to: -7, in: points)?.day, 0)
        XCTAssertEqual(OverviewView.nearest(to: 99, in: points)?.day, 5)
        XCTAssertNil(OverviewView.nearest(to: 3, in: []))
    }

    func testAxisTicksStayShortEnoughToRead() {
        XCTAssertEqual(OverviewView.axisMoney(0), "$0")
        XCTAssertEqual(OverviewView.axisMoney(450), "$450")
        XCTAssertEqual(OverviewView.axisMoney(2500), "$2.5k")
        XCTAssertEqual(OverviewView.axisMoney(12000), "$12k")
    }

    /// Every primary Plaid publishes. If one is missing from the table, its whole branch of the
    /// taxonomy silently lands in Other — which is the bug this bucketing exists to end.
    private static let plaidPrimaries = [
        "INCOME", "TRANSFER_IN", "TRANSFER_OUT", "LOAN_PAYMENTS", "BANK_FEES", "ENTERTAINMENT",
        "FOOD_AND_DRINK", "GENERAL_MERCHANDISE", "HOME_IMPROVEMENT", "MEDICAL", "PERSONAL_CARE",
        "GENERAL_SERVICES", "GOVERNMENT_AND_NON_PROFIT", "TRANSPORTATION", "TRAVEL", "RENT_AND_UTILITIES"
    ]

    func testEveryPlaidPrimaryHasSomewhereToLand() {
        for primary in Self.plaidPrimaries {
            let resolved = SpendingCategory.fromPlaid(primary: primary, detailed: nil)
            XCTAssertNotNil(resolved, "\(primary) resolves to nothing")
            // Income and incoming transfers are excluded from spending, so Other is right for them.
            if primary != "INCOME" && primary != "TRANSFER_IN" {
                XCTAssertNotEqual(resolved, .other, "\(primary) still falls through to Other")
            }
        }
    }

    func testSpendingPrimariesLandWhereAPersonWouldPutThem() {
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "BANK_FEES", detailed: "BANK_FEES_ATM_FEES"), .fees)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "GOVERNMENT_AND_NON_PROFIT", detailed: nil), .government)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "PERSONAL_CARE", detailed: "PERSONAL_CARE_HAIR_AND_BEAUTY"), .personalCare)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "TRAVEL", detailed: "TRAVEL_FLIGHTS"), .travel)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "GENERAL_SERVICES", detailed: "GENERAL_SERVICES_STORAGE"), .services)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "TRANSFER_OUT", detailed: "TRANSFER_OUT_TRANSFER_OUT_FROM_APPS"), .people)
        // A detailed value the app files somewhere other than its primary would.
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "FOOD_AND_DRINK", detailed: "FOOD_AND_DRINK_GROCERIES"), .groceries)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "ENTERTAINMENT", detailed: "ENTERTAINMENT_TV_AND_MOVIES"), .subscriptions)
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "ENTERTAINMENT", detailed: "ENTERTAINMENT_VIDEO_GAMES"), .fun)
        // A detailed value nobody has mapped still resolves through its primary rather than failing.
        XCTAssertEqual(SpendingCategory.fromPlaid(primary: "MEDICAL", detailed: "MEDICAL_SOMETHING_NEW"), .health)
    }

    func testNewKeywordRulesDoNotShadowTheOldOnes() {
        XCTAssertEqual(SpendingCategory.infer(from: "Zelle to Prateek"), .people)
        XCTAssertEqual(SpendingCategory.infer(from: "Amex Send: Add Money"), .people)
        XCTAssertEqual(SpendingCategory.infer(from: "LATE FEE"), .fees)
        XCTAssertEqual(SpendingCategory.infer(from: "Interest Charge on Purchases"), .fees)
        XCTAssertEqual(SpendingCategory.infer(from: "NCDMV"), .government)
        XCTAssertEqual(SpendingCategory.infer(from: "Anthropic"), .subscriptions)
        // The rules are ordered and first-match-wins, so the old ones must still win where they did.
        XCTAssertEqual(SpendingCategory.infer(from: "Trader Joe's"), .groceries)
        XCTAssertEqual(SpendingCategory.infer(from: "Campus Cafe"), .food)
        XCTAssertEqual(SpendingCategory.infer(from: "Uber"), .transport)
        XCTAssertEqual(SpendingCategory.infer(from: "Something unheard of"), .other)
    }

    func testAVagueAnswerFromTheBankLosesToAMerchantWeRecognise() {
        // "Other general services" is the bank admitting it does not know; the name does.
        XCTAssertEqual(SpendingCategory.resolve(primary: "GENERAL_SERVICES", detailed: "GENERAL_SERVICES_OTHER_GENERAL_SERVICES", merchant: "Anthropic"), .subscriptions)
        // A definite answer from the bank still wins over a keyword that would guess otherwise.
        XCTAssertEqual(SpendingCategory.resolve(primary: "GENERAL_SERVICES", detailed: "GENERAL_SERVICES_INSURANCE", merchant: "Auto Owners"), .services)
        // A vague answer with nothing recognisable in the name keeps the bank's bucket.
        XCTAssertEqual(SpendingCategory.resolve(primary: "GENERAL_SERVICES", detailed: "GENERAL_SERVICES_OTHER_GENERAL_SERVICES", merchant: "Qtsr Ltd"), .services)
        // No bank opinion at all falls through to the merchant name.
        XCTAssertEqual(SpendingCategory.resolve(primary: nil, detailed: nil, merchant: "Trader Joe's"), .groceries)
    }

    func testTheBanksOwnWordingIsMadeReadable() {
        XCTAssertEqual(SpendingDetail.name(for: "FOOD_AND_DRINK_COFFEE"), "Coffee")
        XCTAssertEqual(SpendingDetail.name(for: "TRANSPORTATION_TAXIS_AND_RIDE_SHARES"), "Taxis & ride shares")
        XCTAssertEqual(SpendingDetail.name(for: "BANK_FEES_INTEREST_CHARGE"), "Interest charge")
        // The "other" values repeat their own primary; say Other once rather than twice.
        XCTAssertEqual(SpendingDetail.name(for: "FOOD_AND_DRINK_OTHER_FOOD_AND_DRINK"), "Other food & drink")
        // A value invented after this code was written still reads as words, not shouting caps.
        XCTAssertEqual(SpendingDetail.name(for: "MEDICAL_ROBOT_SURGERY"), "Robot surgery")
        XCTAssertFalse(SpendingDetail.name(for: "SOMETHING_ENTIRELY_NEW").contains("_"))
    }

    func testEveryCategoryHasItsOwnColourAndNoneIsPositional() {
        let colours = SpendingCategory.allCases.map { $0.color.description }
        XCTAssertEqual(Set(colours).count, SpendingCategory.allCases.count, "two categories share a colour")
        // The old implementation indexed a nine-item array by position: a tenth case crashed, and
        // inserting one repainted everything after it.
        XCTAssertNotEqual(SpendingCategory.food.color.description, SpendingCategory.travel.color.description)
    }

    @MainActor func testASyncRefilesItsOwnGuessesButNeverTheUsersChoice() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FinanceStore(fileURL: url, demo: false)
        let account = try XCTUnwrap(store.data.accounts.first)
        let payload = PlaidTransactionPayload(id: "p1", merchant: "Delta", amountCents: 45_000, kind: "expense",
                                              date: "2026-09-18", datetime: nil, category: "TRAVEL",
                                              categoryDetailed: "TRAVEL_FLIGHTS", institution: "Amex", pending: false)
        XCTAssertTrue(store.apply(PlaidSync(added: [payload])))
        let stored = try XCTUnwrap(store.data.transactions.first)
        XCTAssertEqual(stored.category, .travel)
        XCTAssertEqual(stored.detailedCategory, "TRAVEL_FLIGHTS", "the bank's own wording is kept, not just used and dropped")

        // A machine guess is the sync's to revise.
        var machineGuessed = stored
        machineGuessed.category = .shopping
        XCTAssertTrue(store.save(machineGuessed))
        XCTAssertTrue(store.apply(PlaidSync(modified: [payload])))
        XCTAssertEqual(store.data.transactions.first?.category, .travel)

        // A choice the user made is not.
        var pinned = try XCTUnwrap(store.data.transactions.first)
        pinned.category = .fun
        pinned.categoryPinned = true
        XCTAssertTrue(store.save(pinned))
        store.apply(PlaidSync(modified: [payload]))
        XCTAssertEqual(store.data.transactions.first?.category, .fun, "a sync overwrote a category the user picked")
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
