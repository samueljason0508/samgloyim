import Foundation

/// A charge that keeps coming back, and where it lands.
struct Subscription: Identifiable, Equatable {
    var id: String { key }
    /// The normalized merchant, so "SPOTIFY USA" and "Spotify USA*" are one subscription.
    var key: String
    var merchant: String
    var latest: Int
    var previous: Int?
    var lastCharged: Date
    var occurrences: Int
    var accountIDs: [UUID]
    var category: SpendingCategory

    /// What it costs over a year at the price it charges now.
    var yearly: Int { latest * 12 }
    /// A rise worth naming. A fall needs no warning.
    var increase: Int? {
        guard let previous, latest > previous else { return nil }
        return latest - previous
    }
    /// The same service billed to two cards is usually two subscriptions nobody meant to have.
    var onSeveralAccounts: Bool { accountIDs.count > 1 }
}

/// Finding the charges that repeat every month.
///
/// Across six accounts a subscription is easy to lose: it is small, it is regular, and it never
/// appears twice on the same statement. This groups by the same normalized merchant the duplicate
/// detector uses, and keeps only what looks genuinely monthly — three or more charges whose gaps
/// sit in the 26–35 day band a monthly bill actually lands in. Fortnightly and weekly charges are
/// left alone rather than quietly annualized at twelve times the wrong number.
enum Recurring {
    static func detect(_ transactions: [Transaction], calendar: Calendar = .current) -> [Subscription] {
        let candidates = transactions.filter { $0.kind == .expense && $0.isTransfer != true }
        let grouped = Dictionary(grouping: candidates) { DuplicateDetector.normalized($0.merchant) }

        return grouped.compactMap { key, rows -> Subscription? in
            let ordered = rows.sorted { $0.date < $1.date }
            guard ordered.count >= 3 else { return nil }

            let gaps = zip(ordered, ordered.dropFirst()).map {
                calendar.dateComponents([.day], from: $0.date, to: $1.date).day ?? 0
            }
            // Every gap has to look monthly. One stray gap means an ordinary shop visited often,
            // not a subscription — and a shop charged to a card monthly by coincidence is not one
            // either, which is why three charges are the minimum.
            guard gaps.allSatisfy({ (26...35).contains($0) }) else { return nil }

            let last = ordered[ordered.count - 1]
            return Subscription(
                key: key,
                merchant: last.merchant,
                latest: last.amount,
                previous: ordered[ordered.count - 2].amount,
                lastCharged: last.date,
                occurrences: ordered.count,
                accountIDs: Array(Set(ordered.map(\.accountID))),
                category: last.category
            )
        }
        .sorted { $0.yearly > $1.yearly }
    }
}
