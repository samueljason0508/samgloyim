import Foundation

struct PlaidTransactionPayload: Decodable {
    var id: String
    var merchant: String
    var amountCents: Int
    var kind: String
    var date: String
    var category: String?
    var institution: String
    var pending: Bool

    func toTransaction(accountID: UUID) -> Transaction {
        let category = SpendingCategory.fromPlaidPrimary(category) ?? SpendingCategory.infer(from: merchant)
        let parsedDate = PlaidService.dateFormatter.date(from: date) ?? Date()
        return Transaction(merchant: merchant, amount: amountCents, date: parsedDate, category: category, accountID: accountID,
            kind: kind == "income" ? .income : .expense, source: .plaid, note: pending ? "Pending at \(institution)" : institution)
    }
}

struct PlaidLinkedItem: Decodable, Identifiable {
    var itemId: String
    var institutionName: String
    var linkedAt: String
    var id: String { itemId }
}

private struct SyncResponse: Decodable {
    var added: [PlaidTransactionPayload]
    var modified: [PlaidTransactionPayload]
    var removed: [String]
}

/// Talks to the local samgloyim backend (backend/server.js), which holds the Plaid
/// client_id/secret and does the token exchange and transaction sync. This app never
/// talks to Plaid's API directly. Backend must be running: `npm start` in `backend/`.
enum PlaidService {
    static let baseURL = URL(string: "http://localhost:5100")!
    /// Plaid posts a bare calendar date with no time or zone. Reading it as UTC puts the
    /// transaction at UTC midnight, which is the *previous* evening anywhere west of London —
    /// a day-early date that also lands transactions in the wrong month and stops duplicate
    /// detection matching the same purchase from another source. It is a local calendar day.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }()

    static func createLinkToken() async throws -> String {
        struct Body: Decodable { var link_token: String }
        let data = try await post("api/create_link_token", body: [String: String]())
        return try JSONDecoder().decode(Body.self, from: data).link_token
    }

    static func exchangePublicToken(_ publicToken: String, institutionName: String) async throws {
        _ = try await post("api/exchange_public_token", body: ["public_token": publicToken, "institution_name": institutionName])
    }

    static func fetchLinkedItems() async throws -> [PlaidLinkedItem] {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("api/items"))
        try validate(response)
        return try JSONDecoder().decode([PlaidLinkedItem].self, from: data)
    }

    static func disconnectItem(_ itemId: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/items/\(itemId)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    static func fetchNewTransactions(accountID: UUID) async throws -> [Transaction] {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("api/transactions"))
        try validate(response)
        let decoded = try JSONDecoder().decode(SyncResponse.self, from: data)
        return decoded.added.map { $0.toTransaction(accountID: accountID) }
    }

    private static func post(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return data
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportError.message("Couldn’t reach the local backend. Make sure it’s running: npm start in the backend/ folder.")
        }
    }
}
