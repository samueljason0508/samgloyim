import SwiftUI

/// "You're at Chipotle — pay with Blue Cash Everyday." Appears only once there is a place to name
/// and a card that beats the others; the rest of the time it stays out of the way.
struct BestCardHere: View {
    @EnvironmentObject var store: FinanceStore
    var addHere: (NearbyPlace) -> Void

    @State private var place: NearbyPlace?
    @State private var looking = false
    @State private var message: String?

    private var ranked: [CardSuggestion] { place.map { store.cards(for: $0.category) } ?? [] }

    var body: some View {
        Group {
            if let place, let pick = CardAdvisor.headline(ranked) {
                Button { addHere(place) } label: { card(place, pick.best, runnerUp: pick.runnerUp) }.buttonStyle(.plain)
            } else if looking || message != nil || place != nil {
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

    private func find() async {
        looking = true; message = nil
        defer { looking = false }
        do {
            place = try await PlaceFinder.nearbyPlaces().first
            if place == nil { message = "Nothing recognisable nearby." }
        } catch {
            message = (error as? ImportError)?.errorDescription ?? error.localizedDescription
        }
    }
}
