import SwiftUI

/// "Which card should I use here?" — finds the places around you, lets you say which one you're
/// actually in, then names the card to pay with.
///
/// It suggests rather than decides. A row of shopfronts is metres apart and the category is what
/// picks the card, so guessing the nearest match would quietly recommend the wrong card. Anywhere
/// can also be searched for by name, which is the way out when the fix is poor or the place is new.
struct BestCardHere: View {
    @EnvironmentObject var store: FinanceStore

    @State private var places: [NearbyPlace] = []
    @State private var chosen: NearbyPlace?
    @State private var looking = false
    @State private var message: String?
    @State private var query = ""
    @State private var searching = false
    @State private var fetchingRates = false
    @State private var rateErrors: [String] = []

    private var ranked: [CardSuggestion] { chosen.map { store.cards(for: $0.category) } ?? [] }
    private var cards: [BankAccount] { store.data.accounts.filter { $0.isCreditCard == true } }

    var body: some View {
        Group {
            if let chosen {
                if let pick = CardAdvisor.headline(ranked) {
                    recommendation(chosen, pick.best, runnerUp: pick.runnerUp)
                } else {
                    diagnosis(chosen)
                }
            } else if looking || searching || !places.isEmpty || message != nil {
                chooser
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

    // MARK: - Choosing where you are

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("WHERE ARE YOU?").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(Palette.muted)
                Spacer()
                if looking || searching { ProgressView().controlSize(.small) }
                Button { reset() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }

            if let message {
                Text(message).font(.system(size: 11)).foregroundStyle(Palette.orange).lineSpacing(3)
            }

            if places.isEmpty && !looking && !searching && message == nil {
                Text("Nothing recognisable nearby. Try searching for it by name.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }

            VStack(spacing: 0) {
                ForEach(places.prefix(6)) { place in
                    Button { chosen = place } label: {
                        HStack(spacing: 10) {
                            Image(systemName: place.category.symbol).font(.system(size: 11)).frame(width: 22)
                                .foregroundStyle(Palette.forest)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(place.category.rawValue).font(.system(size: 9)).foregroundStyle(Palette.muted)
                            }
                            Spacer(minLength: 4)
                            if let metres = place.metresAway {
                                Text("\(metres)m").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Palette.muted)
                        }.padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if place.id != places.prefix(6).last?.id { Divider().overlay(Palette.line).padding(.leading, 32) }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.muted)
                TextField("Set a location by name", text: $query)
                    .font(.system(size: 12)).submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .accessibilityIdentifier("place-search")
                if !query.isEmpty {
                    Button("Search") { Task { await search() } }.font(.system(size: 11, weight: .semibold)).disabled(searching)
                }
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .background(Palette.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 11))

            Button("Look around again") { Task { await find() } }
                .font(.system(size: 11, weight: .semibold)).disabled(looking)
        }.pocketCard(padding: 16)
    }

    // MARK: - The answer

    private func recommendation(_ place: NearbyPlace, _ best: CardSuggestion, runnerUp: CardSuggestion?) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Image(systemName: "location.fill").font(.system(size: 9))
                Text(place.name.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2).lineLimit(1)
                Spacer()
                Button { chosen = nil } label: {
                    Text("NOT HERE?").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.1)
                }.buttonStyle(.plain).accessibilityIdentifier("change-place")
            }.foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 6) {
                Text("Pay with \(best.account.name)").font(.system(size: 21, design: .serif)).foregroundStyle(.white)
                Text(reason(best, runnerUp: runnerUp, at: place)).font(.system(size: 11)).foregroundStyle(Palette.lime).lineSpacing(3)
            }
            ForEach(best.caveats, id: \.self) { caveat in
                Label(caveat, systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
            }
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

    // MARK: - Why there is no answer

    /// Everything the recommendation stands on, when it cannot make one: which place, which cards
    /// were considered, what each is missing — and the button that fixes the usual cause.
    private func diagnosis(_ place: NearbyPlace) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "location.fill").font(.system(size: 9))
                Text(place.name.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2).lineLimit(1)
                Spacer()
                Button { chosen = nil } label: {
                    Text("NOT HERE?").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.1)
                }.buttonStyle(.plain).accessibilityIdentifier("change-place")
            }.foregroundStyle(Palette.muted)

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
        }.pocketCard(padding: 16)
    }

    // MARK: - Work

    private func find() async {
        looking = true; message = nil; rateErrors = []; chosen = nil
        defer { looking = false }
        do {
            places = try await PlaceFinder.nearbyPlaces()
        } catch {
            places = []
            message = (error as? ImportError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searching = true; message = nil
        defer { searching = false }
        do {
            let found = try await PlaceFinder.search(text)
            if found.isEmpty { message = "Nothing found for “\(text)”." } else { places = found }
        } catch {
            message = (error as? ImportError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fetchRates() async {
        fetchingRates = true; rateErrors = []
        defer { fetchingRates = false }
        for card in cards where (card.rewards ?? []).isEmpty {
            do { try await store.lookUpRewards(for: card) }
            catch { rateErrors.append("\(card.name): \((error as? ImportError)?.errorDescription ?? error.localizedDescription)") }
        }
    }

    private func reset() {
        places = []; chosen = nil; message = nil; query = ""; rateErrors = []
    }
}
