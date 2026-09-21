import Foundation

struct PlaidTransactionPayload: Decodable {
    var id: String
    var merchant: String
    var amountCents: Int
    var kind: String
    var date: String
    var datetime: String?
    var category: String?
    var categoryDetailed: String?
    var institution: String
    var pending: Bool

    func toTransaction(accountID: UUID) -> Transaction {
        let category = SpendingCategory.resolve(primary: category, detailed: categoryDetailed, merchant: merchant)
        let parsedDate = PlaidService.timestamp(from: datetime) ?? PlaidService.dateFormatter.date(from: date) ?? Date()
        return Transaction(merchant: merchant, amount: amountCents, date: parsedDate, category: category, accountID: accountID,
            kind: kind == "income" ? .income : .expense, source: .plaid,
            note: pending ? "Pending at \(institution)" : institution, externalID: id,
            detailedCategory: categoryDetailed,
            isTransfer: SpendingCategory.isTransfer(primary: self.category, detailed: categoryDetailed, merchant: merchant))
    }
}

/// One sync as the bank reported it. Rows stay as payloads: which account each belongs to is the
/// ledger's business, not the network layer's, and a payload knows only its institution.
/// One card or bank as Plaid describes it. `officialName` is the product — "Blue Cash Everyday®" —
/// which is what earn rates can be looked up against; `name` is whatever the bank shows the user.
struct PlaidAccountPayload: Decodable {
    var accountId: String
    var name: String
    var officialName: String?
    var mask: String?
    var subtype: String?
    var isCreditCard: Bool
    var institution: String

    /// The product name to look rates up by, falling back to the display name when the bank has no
    /// official one, and to nothing at all when neither says anything useful.
    var productName: String? {
        let candidate = (officialName ?? name).trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : "\(institution) \(candidate)"
    }
}

struct PlaidSync {
    var accounts: [PlaidAccountPayload] = []
    var added: [PlaidTransactionPayload] = []
    var modified: [PlaidTransactionPayload] = []
    var removed: [String] = []
    /// One entry per linked bank. A sync that brought nothing and a sync where two banks
    /// failed look identical in the rows alone.
    var status: [PlaidItemStatus] = []
    var isEmpty: Bool { added.isEmpty && modified.isEmpty && removed.isEmpty }
    var troubled: [PlaidItemStatus] { status.filter { !$0.ok } }
}

/// How one bank's own sync went. Older backends do not send this, so everything is optional
/// and an absent status means "nothing to report", not "broken".
struct PlaidItemStatus: Decodable, Identifiable {
    var itemId: String
    var institutionName: String
    var ok: Bool
    var needsReauth: Bool?
    var error: String?
    var lastSyncedAt: String?
    var id: String { itemId }
    /// The only failure the user can do anything about, and the only one worth a button.
    var wantsSignIn: Bool { !ok && needsReauth == true }
}

struct PlaidLinkedItem: Decodable, Identifiable {
    var itemId: String
    var institutionName: String
    var linkedAt: String
    /// Written by the backend on every successful sync; absent until this bank has had one.
    var lastSyncedAt: String?
    var lastError: String?
    var id: String { itemId }
    var needsSignIn: Bool { lastError == "ITEM_LOGIN_REQUIRED" }
}

private struct SyncResponse: Decodable {
    var accounts: [PlaidAccountPayload]
    var added: [PlaidTransactionPayload]
    var modified: [PlaidTransactionPayload]
    var removed: [String]
    var status: [PlaidItemStatus]?
}

/// Talks to the local samgloyim backend (backend/server.js), which holds the Plaid
/// client_id/secret and does the token exchange and transaction sync. This app never
/// talks to Plaid's API directly. Backend must be running: `npm start` in `backend/`.
enum PlaidService {
    /// Where the backend lives.
    ///
    /// `localhost` is right on the simulator, where the app and the server share a machine. On a
    /// real device localhost is the phone itself and nothing is listening there, so a build that
    /// leaves the simulator needs to be told the machine's address instead — which is why this is
    /// a setting rather than a constant.
    static let defaultBaseURL = URL(string: "http://localhost:5100")!
    static let addressKey = "backendAddress"
    static var baseURL: URL { resolve(UserDefaults.standard.string(forKey: addressKey)) }

    /// Typed by hand on a phone keyboard, so forgive what can be forgiven — a missing scheme,
    /// a trailing slash, surrounding space — and fall back to the default rather than refuse to
    /// build a URL at all. A stored address that no longer parses must not strand the app.
    static func resolve(_ typed: String?) -> URL {
        guard var text = typed?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return defaultBaseURL
        }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return defaultBaseURL }
        return url
    }

    /// Every request goes through here, so that no call site can forget to carry the token.
    static func request(_ path: String, method: String = "GET", token: String? = BackendCredential.token) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        // A free host sleeps when idle and takes most of a minute to wake, so the first
        // request after a quiet spell is slow rather than broken. Wait it out.
        request.timeoutInterval = 90
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Trades a name and password for the backend's access token, which is what every other
    /// request carries. The password is never stored — only what it buys.
    static func logIn(username: String, password: String) async throws -> String {
        struct Reply: Decodable { var token: String }
        struct Complaint: Decodable { var error: String? }
        var request = request("login", method: "POST", token: nil)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        // The backend already words these for a person — a refused password and a throttled
        // address need different patience, and only it knows which happened.
        guard (200..<300).contains(code) else {
            let said = (try? JSONDecoder().decode(Complaint.self, from: data))?.error
            throw ImportError.message(said ?? "Couldn’t sign in to the backend at \(baseURL.absoluteString).")
        }
        return try JSONDecoder().decode(Reply.self, from: data).token
    }

    /// Whether the backend answers, and whether it accepts us, said in a sentence the user
    /// can act on. Reachable-but-refused and not-there-at-all need different fixes.
    static func check() async -> String {
        struct Health: Decodable { var ok: Bool; var env: String?; var authorized: Bool? }
        var probe = request("health")
        // Shorter than a real request: a wrong address should say so rather than sit there.
        // Long enough that a sleeping free host usually gets a word in first.
        probe.timeoutInterval = 25
        do {
            let (data, response) = try await URLSession.shared.data(for: probe)
            try validate(response)
            let health = try JSONDecoder().decode(Health.self, from: data)
            guard health.ok else { return "Answered, but reported a problem." }
            guard health.authorized == true else {
                return BackendCredential.token == nil
                    ? "Reachable, but no access token set. It is printed when the backend starts."
                    : "Reachable, but it rejected this access token."
            }
            return "Reachable — Plaid \(health.env ?? "?")"
        } catch let error as ImportError {
            return error.errorDescription ?? "Couldn’t reach it."
        } catch {
            return "No answer from \(baseURL.absoluteString). Check it is running and reachable from this device — a free host that has been idle can take a minute to wake, so this is worth a second try."
        }
    }
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

    private static let isoFormatter = ISO8601DateFormatter()

    /// A real clock time for a transaction, when the bank sent one. Most don't: Plaid returns
    /// these fields only for select institutions, and some of those fill them with a midnight
    /// placeholder. A placeholder is not a time, so it falls back to the plain calendar date.
    static func timestamp(from datetime: String?) -> Date? {
        guard let datetime, let parsed = isoFormatter.date(from: datetime) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "UTC") else { return nil }
        utc.timeZone = zone
        let parts = utc.dateComponents([.hour, .minute, .second], from: parsed)
        guard parts.hour != 0 || parts.minute != 0 || parts.second != 0 else { return nil }
        return parsed
    }

    static func createLinkToken() async throws -> String {
        struct Body: Decodable { var link_token: String }
        let data = try await post("api/create_link_token", body: [String: String]())
        return try JSONDecoder().decode(Body.self, from: data).link_token
    }

    static func exchangePublicToken(_ publicToken: String, institutionName: String) async throws {
        _ = try await post("api/exchange_public_token", body: ["public_token": publicToken, "institution_name": institutionName])
    }

    static func fetchLinkedItems() async throws -> [PlaidLinkedItem] {
        let (data, response) = try await URLSession.shared.data(for: request("api/items"))
        try validate(response)
        return try JSONDecoder().decode([PlaidLinkedItem].self, from: data)
    }

    static func disconnectItem(_ itemId: String) async throws {
        let request = request("api/items/\(itemId)", method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    /// A sync reports new rows, corrections to rows it sent before, and rows that never posted.
    /// Dropping the last two leaves pending purchases frozen at their raw card descriptor.
    static func fetchSync() async throws -> PlaidSync {
        let (data, response) = try await URLSession.shared.data(for: request("api/transactions"))
        try validate(response)
        let decoded = try JSONDecoder().decode(SyncResponse.self, from: data)
        return PlaidSync(accounts: decoded.accounts, added: decoded.added, modified: decoded.modified, removed: decoded.removed, status: decoded.status ?? [])
    }

    static func post(_ path: String, body: [String: String]) async throws -> Data {
        var request = request(path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return data
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ImportError.message("The backend gave an answer this app couldn’t read.")
        }
        // A rejected token and an absent server both look like "sync failed", and the fixes are
        // nothing alike — so say which one it is.
        if http.statusCode == 401 {
            throw ImportError.message(BackendCredential.token == nil
                ? "The backend needs its access token. It is printed when the backend starts; add it under Import › Sync server."
                : "The backend rejected this access token. Check it under Import › Sync server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ImportError.message("Couldn’t reach the backend. Make sure it’s running, and that the address under Import › Sync server is right.")
        }
    }
}
