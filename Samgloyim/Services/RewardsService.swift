import Foundation

/// Looks up what a card earns. No issuer publishes rates as an API, but every one of them publishes
/// them on the open web, so the backend searches for whatever card the bank reported rather than the
/// app shipping a fixed table of products that would be wrong for anyone else's wallet — and stale
/// for everyone once a rotating category turns over.
enum RewardsService {
    private struct Response: Decodable {
        var card: String
        var rates: [Row]
        var sources: [String]?

        struct Row: Decodable {
            var category: String?
            var percent: Double
            var startsOn: String?
            var endsOn: String?
            var capCents: Int?
            var needsActivation: Bool?
            var note: String?
        }
    }

    static func lookup(card: String) async throws -> [RewardRate] {
        let data = try await PlaidService.post("api/card-rewards", body: ["card": card])
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.rates.compactMap { row in
            // A rate nobody can express as a percentage is not a rate; drop it rather than show 0%.
            guard row.percent > 0 else { return nil }
            return RewardRate(category: row.category.flatMap(SpendingCategory.init(rawValue:)),
                              basisPoints: Int((row.percent * 100).rounded()),
                              startsOn: row.startsOn.flatMap(CSVService.parseDate),
                              endsOn: row.endsOn.flatMap(CSVService.parseDate),
                              capCents: row.capCents,
                              needsActivation: row.needsActivation ?? false,
                              note: row.note ?? "")
        }
    }
}
