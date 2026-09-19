import Foundation

struct ImportResult {
    var transactions: [Transaction]
    var warnings: [String]
}

enum ImportError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

enum CSVService {
    static func rows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closedQuote = false
        let chars = Array(text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(char) }
            } else if char == "," {
                row.append(field); field = ""; closedQuote = false
            } else if char == "\n" {
                row.append(field)
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []; field = ""; closedQuote = false
            } else if char == "\"" && field.isEmpty && !closedQuote { quoted = true }
            else if closedQuote {
                guard char == " " || char == "\t" else { throw ImportError.message("Unexpected text after a quoted CSV value.") }
            } else if char == "\"" { throw ImportError.message("A CSV value contains an unescaped quote.") }
            else { field.append(char) }
            index += 1
        }
        guard !quoted else { throw ImportError.message("The CSV has an unfinished quoted value.") }
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
        return rows
    }

    static func parse(_ text: String, accounts: [BankAccount], defaultAccountID: UUID) throws -> ImportResult {
        guard text.utf8.count <= 5_000_000 else { throw ImportError.message("Choose a CSV smaller than 5 MB.") }
        let rows = try rows(text)
        guard let header = rows.first, rows.count > 1 else { throw ImportError.message("This CSV needs a header and at least one transaction.") }
        guard rows.count <= 10_001 else { throw ImportError.message("Import up to 10,000 transactions at a time.") }
        let keys = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(keys).count == keys.count else { throw ImportError.message("The CSV has duplicate column names.") }
        for required in ["date", "merchant", "amount"] {
            guard keys.contains(required) else { throw ImportError.message("Missing the ‘\(required)’ column. Required columns: date, merchant, amount.") }
        }
        var transactions: [Transaction] = [], warnings: [String] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            func value(_ key: String) -> String {
                guard let index = keys.firstIndex(of: key), index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            func skip(_ reason: String) { warnings.append("Row \(offset + 2): \(reason)") }
            guard row.count == header.count else { skip("column count doesn’t match the header."); continue }
            guard let date = parseDate(value("date")) else { skip("use a date like 2026-09-18 or 09/18/2026."); continue }
            let merchant = value("merchant")
            guard !merchant.isEmpty else { skip("merchant is empty."); continue }
            guard let signedAmount = Money.parse(value("amount")), signedAmount != 0 else { skip("amount must be a nonzero USD value with at most two decimals."); continue }
            let kindText = value("kind").lowercased()
            guard kindText.isEmpty || ["income", "expense"].contains(kindText) else { skip("kind must be income or expense."); continue }
            let accountName = value("account")
            var accountID = defaultAccountID
            if !accountName.isEmpty {
                let matches = accounts.filter { $0.name.caseInsensitiveCompare(accountName) == .orderedSame }
                guard matches.count == 1, let account = matches.first else { skip("account ‘\(accountName)’ isn’t a unique existing account. Create or rename it first."); continue }
                accountID = account.id
            }
            let category = SpendingCategory.allCases.first { $0.rawValue.caseInsensitiveCompare(value("category")) == .orderedSame }
                ?? SpendingCategory.infer(from: merchant)
            transactions.append(Transaction(merchant: merchant, amount: abs(signedAmount), date: date, category: category,
                accountID: accountID, kind: kindText == "income" ? .income : .expense, source: .csv, note: value("note")))
        }
        return ImportResult(transactions: transactions, warnings: warnings)
    }

    static func parseDate(_ text: String) -> Date? {
        for format in ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: text), formatter.string(from: date) == text { return date }
        }
        return nil
    }

    static func export(_ transactions: [Transaction], accounts: [BankAccount]) -> String {
        func quote(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: trimmed.hasPrefix) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let rows = transactions.sorted { $0.date > $1.date }.map { transaction in
            [formatter.string(from: transaction.date), transaction.merchant, Money.input(transaction.amount),
             transaction.category.rawValue, accounts.first { $0.id == transaction.accountID }?.name ?? "",
             transaction.kind.rawValue.lowercased(), transaction.note].map(quote).joined(separator: ",")
        }
        return (["date,merchant,amount,category,account,kind,note"] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
