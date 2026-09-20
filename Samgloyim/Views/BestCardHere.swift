import SwiftUI

/// "You're at Chipotle — pay with Blue Cash Everyday." Appears only once there is a place to name
/// and a card that beats the others; the rest of the time it stays out of the way.
struct BestCardHere: View {
    @EnvironmentObject var store: FinanceStore
    var addHere: (NearbyPlace) -> Void

    @State private var places: [NearbyPlace] = []
    @State private var chosen: NearbyPlace?
    @State private var looking = false
    @State private var fetchingRates = false
    @State private var rateErrors: [String] = []
    @State private var message: String?

    private var place: NearbyPlace? { chosen ?? places.first }
    private var ranked: [CardSuggestion] { place.map { store.cards(for: $0.category) } ?? [] }
    private var cards: [BankAccount] { store.data.accounts.filter { $0.isCreditCard == true } }

    var body: some View {
        Group {
            if let place, let pick = CardAdvisor.headline(ranked) {
                Button { addHere(place) } label: { card(place, pick.best, runnerUp: pick.runnerUp) }.buttonStyle(.plain)
            } else if place != nil {
                diagnosis
            } else if looking || message != nil {
                status
            } else {
                Button { Task { await find() } } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "location.magnifyingglass").font(.system(size: 13))
                        Text("Which card should I use here?").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }.pocketCard(padding: 15)
                }.buttonStyle(.plain).accessibilityIdentifier("best-card-here")
            }
        }
    }

    private func card(_ place: NearbyPlace, _ best: CardSuggestion, runnerUp: CardSuggestion?) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Image(systemName: "location.fill").font(.system(size: 9))
                Text(place.name.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2).lineLimit(1)
                Spacer()
                Text("\(place.metresAway)m").font(.system(size: 9, design: .monospaced))
            }.foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 6) {
                Text("Pay with \(best.account.name)").font(.system(size: 21, design: .serif)).foregroundStyle(.white)
                Text(reason(best, runnerUp: runnerUp, at: place)).font(.system(size: 11)).foregroundStyle(Palette.lime).lineSpacing(3)
            }
            ForEach(best.caveats, id: \.self) { caveat in
                Label(caveat, systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
            }
            HStack(spacing: 6) {
                Text("Add a purchase here").font(.system(size: 11, weight: .semibold))
                Image(systemName: "arrow.up.right").font(.system(size: 9))
            }.foregroundStyle(Palette.ink).padding(.horizontal, 13).padding(.vertical, 10).background(Palette.lime, in: Capsule())
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Palette.forest, in: RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("best-card-result")
    }

    private func reason(_ best: CardSuggestion, runnerUp: CardSuggestion?, at place: NearbyPlace) -> String {
        let rate = best.rate?.percentText ?? "more"
        guard let runnerUp else { return "\(rate) back on \(place.category.rawValue.lowercased())." }
        let theirs = runnerUp.basisPoints > 0 ? (runnerUp.rate?.percentText ?? "less") : "nothing"
        return "\(rate) back on \(place.category.rawValue.lowercased()) — \(runnerUp.account.name) gives \(theirs)."
    }

    private var status: some View {
        HStack(spacing: 9) {
            if looking { ProgressView().controlSize(.small) } else { Image(systemName: "location.slash").font(.system(size: 12)) }
            Text(looking ? "Looking around…" : (message ?? noCardMessage)).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Spacer()
            if !looking {
                Button("Try again") { Task { await find() } }.font(.system(size: 11, weight: .semibold))
            }
        }.pocketCard(padding: 14)
    }

    /// A place was found but no card can be recommended — almost always because no rates are set yet.
    private var noCardMessage: String {
        guard let place else { return "Nothing nearby." }
        return store.data.accounts.contains { $0.isCreditCard == true }
            ? "You're at \(place.name), but none of your cards has rates yet. Add them in Settings."
            : "You're at \(place.name). Connect a card to compare rates."
    }

    /// Everything the recommendation is standing on, when it cannot make one. Which place, which
    /// other places were nearby, which cards were considered, and what each one is missing — plus
    /// the one button that fixes the usual cause.
    private var diagnosis: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let place {
                HStack(spacing: 7) {
                    Image(systemName: "location.fill").font(.system(size: 9))
                    Text(place.name.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2).lineLimit(1)
                    Spacer()
                    Text("\(place.metresAway)m · \(place.category.rawValue)").font(.system(size: 9, design: .monospaced))
                }.foregroundStyle(Palette.muted)
            }

            if cards.isEmpty {
                Text("No credit cards connected. Only cards earn rewards, so there's nothing to compare yet.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
            } else {
                VStack(spacing: 8) {
                    ForEach(cards) { card in
                        HStack(spacing: 8) {
                            Image(systemName: "creditcard.fill").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            Text(card.officialName ?? card.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            let count = (card.rewards ?? []).count
                            Text(count == 0 ? "no rates" : "\(count) rates")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(count == 0 ? Palette.orange : Palette.forest)
                        }
                    }
                }
                Button { Task { await fetchRates() } } label: {
                    HStack(spacing: 8) {
                        if fetchingRates { ProgressView().controlSize(.small) } else { Image(systemName: "sparkle.magnifyingglass").font(.system(size: 11)) }
                        Text(fetchingRates ? "Looking up published rates…" : "Look up rates for \(cards.count) card\(cards.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .semibold))
                    }.frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Palette.lime, in: Capsule()).foregroundStyle(Palette.ink)
                }.buttonStyle(.plain).disabled(fetchingRates).accessibilityIdentifier("lookup-rates-here")
                ForEach(rateErrors, id: \.self) { error in
                    Text(error).font(.system(size: 10)).foregroundStyle(Palette.orange).lineSpacing(2)
                }
                Text("Or enter them yourself in Settings › the card › Rewards.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }

            if places.count > 1 {
                Divider().overlay(Palette.line)
                Text("SOMEWHERE ELSE?").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.1).foregroundStyle(Palette.muted)
                // MapKit can pick the shop next door, and the category decides which card wins.
                ForEach(places.prefix(4).filter { $0.id != place?.id }) { other in
                    Button { chosen = other } label: {
                        HStack(spacing: 8) {
                            Text(other.name).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(other.metresAway)m · \(other.category.rawValue)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }

            Button("Look around again") { Task { await find() } }
                .font(.system(size: 11, weight: .semibold)).disabled(looking)
        }.pocketCard(padding: 16)
    }

    private func fetchRates() async {
        fetchingRates = true; rateErrors = []
        defer { fetchingRates = false }
        for card in cards where (card.rewards ?? []).isEmpty {
            do { try await store.lookUpRewards(for: card) }
            catch { rateErrors.append("\(card.name): \((error as? ImportError)?.errorDescription ?? error.localizedDescription)") }
        }
    }

    private func find() async {
        looking = true; message = nil; rateErrors = []; chosen = nil
        defer { looking = false }
        do {
            places = try await PlaceFinder.nearbyPlaces()
            if places.isEmpty { message = "Nothing recognisable nearby." }
        } catch {
            message = (error as? ImportError)?.errorDescription ?? error.localizedDescription
        }
    }
}
