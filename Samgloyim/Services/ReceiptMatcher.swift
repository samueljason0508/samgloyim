import Foundation

struct ReceiptMatch: Identifiable, Equatable {
    var transaction: Transaction
    var score: Int
    var reasons: [String]
    var id: UUID { transaction.id }
}

enum ReceiptMatcher {
    /// Card networks post a purchase up to a few days after it happens, so a receipt dated
    /// the 3rd can legitimately belong to a purchase that cleared on the 6th.
    static let dateWindowDays = 4
    private static let suggestionThreshold = 3

    /// Purchases a receipt could still belong to: expenses that don't already carry one.
    static func candidates(in transactions: [Transaction]) -> [Transaction] {
        transactions.filter { $0.kind == .expense && $0.receipt == nil }
    }

    /// Ranked matches for a reading, best first.
    ///
    /// An exact cents match is required. A receipt total that equals no purchase is never
    /// approximated onto the nearest one — that case returns empty and the user maps it by hand.
    static func matches(for reading: ReceiptReading, in transactions: [Transaction],
                        now: Date = Date(), calendar: Calendar = .current) -> [ReceiptMatch] {
        guard let total = reading.amount, total > 0 else { return [] }
        let scanned = DuplicateDetector.normalized(reading.merchant)
        let reference = calendar.startOfDay(for: reading.date ?? now)
        return candidates(in: transactions).compactMap { transaction in
            guard transaction.amount == total else { return nil }
            let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: transaction.date), to: reference).day ?? Int.max)
            guard days <= dateWindowDays else { return nil }
            var score = 1
            var reasons = ["Total matches exactly"]
            if days == 0 { score += 2; reasons.append("Same day") }
            else { score += 1; reasons.append("\(days) day\(days == 1 ? "" : "s") apart") }
            let purchase = DuplicateDetector.normalized(transaction.merchant)
            if !scanned.isEmpty, !purchase.isEmpty, purchase.contains(scanned) || scanned.contains(purchase) {
                score += 2
                reasons.append("Merchant looks the same")
            }
            return ReceiptMatch(transaction: transaction, score: score, reasons: reasons)
        }.sorted { $0.score == $1.score ? $0.transaction.date > $1.transaction.date : $0.score > $1.score }
    }

    /// The one match worth putting in front of the user to confirm. A tie between two equally
    /// good purchases is not a match — offering either would be a coin flip on their money.
    static func suggestion(from matches: [ReceiptMatch]) -> ReceiptMatch? {
        guard let best = matches.first, best.score >= suggestionThreshold else { return nil }
        guard matches.count == 1 || matches[1].score < best.score else { return nil }
        return best
    }
}
