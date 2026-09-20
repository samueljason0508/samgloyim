import Foundation

struct CardSuggestion: Identifiable, Equatable {
    var account: BankAccount
    var basisPoints: Int
    var rate: RewardRate?
    var caveats: [String]
    var id: UUID { account.id }
}

/// Ranks the cards in a wallet for one kind of purchase.
///
/// Rates expire. A rotating category runs for a quarter, a welcome rate for a year, and a card that
/// earned 5% here last month may earn 1% today — so every rate is checked against the date rather
/// than taken at face value, and a rate that has run out is said out loud instead of silently
/// dropping the card down the list.
enum CardAdvisor {
    static func rank(_ accounts: [BankAccount], for category: SpendingCategory, now: Date = Date()) -> [CardSuggestion] {
        accounts.filter { $0.isCreditCard == true }.map { account in
            let rates = account.rewards ?? []
            let live = rates.filter { $0.applies(on: now) }
            let best = bestRate(in: live, for: category)
            var caveats: [String] = []
            if let best {
                if best.needsActivation { caveats.append("needs activating with \(account.name)") }
                if let cap = best.capCents { caveats.append("up to \(Money.format(cap, decimals: false)) of spending") }
                if !best.note.isEmpty { caveats.append(best.note) }
            }
            // A rate that has just run out is the most misleading thing on the screen: the card was
            // the right answer recently and the user may still believe it is.
            if let lapsed = rates.first(where: { $0.category == category && !$0.applies(on: now) && ($0.endsOn ?? .distantFuture) < now }) {
                caveats.append("\(lapsed.percentText) here ended \(lapsed.endsOn?.formatted(.dateTime.month(.abbreviated).day()) ?? "recently") — check the current categories")
            }
            if let upcoming = rates.first(where: { $0.category == category && ($0.startsOn ?? .distantPast) > now }) {
                caveats.append("\(upcoming.percentText) here from \(upcoming.startsOn?.formatted(.dateTime.month(.abbreviated).day()) ?? "soon")")
            }
            return CardSuggestion(account: account, basisPoints: best?.basisPoints ?? 0, rate: best, caveats: caveats)
        }
        .sorted { ($0.basisPoints, $1.account.name) > ($1.basisPoints, $0.account.name) }
    }

    /// The category's own rate when the card has one, otherwise the card's catch-all.
    private static func bestRate(in rates: [RewardRate], for category: SpendingCategory) -> RewardRate? {
        let matching = rates.filter { $0.category == category }.max { $0.basisPoints < $1.basisPoints }
        return matching ?? rates.filter { $0.category == nil }.max { $0.basisPoints < $1.basisPoints }
    }

    /// Nothing worth saying unless one card actually beats another.
    static func headline(_ suggestions: [CardSuggestion]) -> (best: CardSuggestion, runnerUp: CardSuggestion?)? {
        guard let best = suggestions.first, best.basisPoints > 0 else { return nil }
        let runnerUp = suggestions.dropFirst().first { $0.basisPoints < best.basisPoints }
        return (best, runnerUp)
    }
}
