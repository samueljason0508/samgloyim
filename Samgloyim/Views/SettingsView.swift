import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct SettingsView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var accountRequest: AccountRequest?
    private struct AccountRequest: Identifiable {
        let id = UUID()
        var account: BankAccount?
    }
    @State private var resetAction: ResetAction?
    @State private var export = false
    @State private var exportError: String?
    @State private var exportDocument = CSVDocument(text: "")
    @State private var linkedBanks: [PlaidLinkedItem] = []
    @State private var disconnectError: String?
    /// The account waiting to be folded into another one.
    @State private var mergeSource: BankAccount?
    enum ResetAction: String, Identifiable { case empty, demo; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 13) {
                        PocketBloomMark(pocket: Palette.forest, leaf: Palette.sprout, cut: Palette.paper)
                            .frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 5) { PocketBloomWordmark(size: 26); Text("A little clarity, every day.").font(.subheadline).foregroundStyle(Palette.muted) }
                    }.padding(.vertical, 9)
                }
                Section {
                    ForEach(store.data.accounts) { account in
                        Button { accountRequest = AccountRequest(account: account) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: account.symbol).frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) { Text(account.name).font(.system(size: 15, weight: .medium)); Text(account.detail).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                                Spacer()
                                Text(Money.format(store.balance(account))).font(.system(size: 13, weight: .medium))
                            }.padding(.vertical, 5)
                        }.buttonStyle(.plain)
                        // Two accounts for one card — an old link beside a new one — make every
                        // per-account total wrong, and nothing else in the app can put that right.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if store.data.accounts.count > 1 {
                                Button { mergeSource = account } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                                    .tint(Palette.orange)
                                    .accessibilityIdentifier("merge-account")
                            }
                        }
                    }
                    Button { accountRequest = AccountRequest(account: nil) } label: { Label("Add account", systemImage: "plus") }.accessibilityIdentifier("add-account")
                } header: { Text("Your accounts") } footer: { Text("Tracked balances = opening balance + all recorded income − all recorded expenses. These aren’t live bank balances.") }
                if !linkedBanks.isEmpty {
                    Section {
                        ForEach(linkedBanks) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.needsSignIn ? "exclamationmark.triangle.fill" : "building.columns.fill")
                                    .frame(width: 32).foregroundStyle(item.needsSignIn ? Palette.orange : Palette.forest)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.institutionName).font(.system(size: 15, weight: .medium))
                                    Text(syncLine(item))
                                        .font(.system(size: 11))
                                        .foregroundStyle(item.needsSignIn ? Palette.orange : Palette.muted)
                                        .accessibilityIdentifier("bank-sync-state")
                                }
                                Spacer()
                                Button(role: .destructive) { Task { await disconnect(item) } } label: { Image(systemName: "trash") }
                            }.padding(.vertical, 5)
                        }
                    } header: { Text("Connected banks") } footer: { Text("Connections are read-only: this app can only see transactions, never move money. Disconnecting revokes access immediately. A bank asking you to sign in again keeps its place in the queue — the others still sync meanwhile.") }
                }
                Section("Your data") {
                    Button {
                        exportDocument = CSVDocument(text: CSVService.export(store.data.transactions, accounts: store.data.accounts)); export = true
                    } label: { Label("Export transactions as CSV", systemImage: "square.and.arrow.up") }
                    if store.data.isDemo { Label("Sample data is enabled", systemImage: "sparkles").foregroundStyle(Palette.muted) }
                    Button("Start fresh with my own data") { resetAction = .empty }.accessibilityIdentifier("start-fresh")
                    Button("Restore sample data") { resetAction = .demo }
                }
                Section("Built for this first version") {
                    feature("On-device receipt reading", detail: "Choose receipt images from Photos or Files, then check the extracted merchant, total, date, and category.")
                    feature("Read-only bank sync", detail: "Connect a bank via Plaid to sync transactions automatically. This app can only read transaction data — it can never move money, and you can disconnect a bank anytime above.")
                    feature("Accounts you control", detail: "Add transactions manually or import them. Apple Wallet isn’t connected in this version.")
                    feature("Clear spending insights", detail: "Charts and monthly notes use your recorded data. Card reward rates are looked up from what issuers publish, and you can correct any of them.")
                }
                Section { Text("Your data is saved locally on this device. This app has no backend, analytics, or sign-in. It uses USD for all amounts. Export your transactions before deleting the app.").font(.footnote).foregroundStyle(Palette.muted) }
            }.scrollContentBackground(.hidden).pageBackground().navigationTitle("Make it yours").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $accountRequest) { AccountEditor(account: $0.account) }
                .confirmationDialog(resetAction == .empty ? "Start with a clean slate?" : "Replace everything with sample data?", isPresented: Binding(get: { resetAction != nil }, set: { if !$0 { resetAction = nil } }), titleVisibility: .visible) {
                    Button(resetAction == .empty ? "Clear data and start fresh" : "Replace with sample data", role: .destructive) { if let resetAction, store.reset(useDemo: resetAction == .demo) { self.resetAction = nil; dismiss() } }
                    Button("Cancel", role: .cancel) { resetAction = nil }
                } message: { Text("This removes existing transactions and accounts. Export any transactions you want to keep first.") }
                .fileExporter(isPresented: $export, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "samgloyim-transactions") { result in
                    if case .failure(let error) = result { exportError = error.localizedDescription }
                }
                .alert("Export couldn’t finish", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) { Button("OK") { exportError = nil } } message: { Text(exportError ?? "Try again.") }
                .alert("Couldn’t disconnect", isPresented: Binding(get: { disconnectError != nil }, set: { if !$0 { disconnectError = nil } })) { Button("OK") { disconnectError = nil } } message: { Text(disconnectError ?? "Try again.") }
                .confirmationDialog("Merge \(mergeSource?.name ?? "this account") into…",
                                    isPresented: Binding(get: { mergeSource != nil }, set: { if !$0 { mergeSource = nil } }),
                                    titleVisibility: .visible, presenting: mergeSource) { source in
                    ForEach(store.data.accounts.filter { $0.id != source.id }) { target in
                        Button(target.name) { store.mergeAccount(source.id, into: target.id); mergeSource = nil }
                    }
                    Button("Cancel", role: .cancel) { mergeSource = nil }
                } message: { source in
                    Text("Every transaction in \(source.name) moves across and \(source.name) is removed. Balances add up. This can’t be undone.")
                }
                .task { await loadLinkedBanks() }
        }
    }
    private func feature(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 14, weight: .medium)); Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3) }.padding(.vertical, 7)
    }
    @MainActor private func loadLinkedBanks() async {
        linkedBanks = (try? await PlaidService.fetchLinkedItems()) ?? []
    }
    @MainActor private func disconnect(_ item: PlaidLinkedItem) async {
        do { try await PlaidService.disconnectItem(item.itemId); await loadLinkedBanks() }
        catch { disconnectError = error.localizedDescription }
    }
    /// What this bank is doing, in the order the user cares about: what is broken, then how
    /// current it is, then — only if it has never synced — when it was connected.
    ///
    /// ponytail: re-authenticating means disconnect and reconnect. Plaid's update mode would
    /// spare that round trip; it needs a link token minted against the existing item.
    private func syncLine(_ item: PlaidLinkedItem) -> String {
        if item.needsSignIn { return "Needs you to sign in again — disconnect and reconnect it" }
        if let last = item.lastSyncedAt { return "Read-only · synced \(formattedAgo(last))" }
        if item.lastError != nil { return "Read-only · last sync didn’t go through" }
        return "Read-only · connected \(formattedDate(item.linkedAt))"
    }

    /// A sync is judged by how stale it is, not by what date it happened on.
    private func formattedAgo(_ iso: String) -> String {
        ISO8601DateFormatter().date(from: iso).map { $0.formatted(.relative(presentation: .named)) } ?? "recently"
    }

    private func formattedDate(_ iso: String) -> String {
        ISO8601DateFormatter().date(from: iso).map { $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "recently"
    }
}

struct AccountEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    var account: BankAccount?
    @State private var name = ""
    @State private var detail = "Checking"
    @State private var opening = "0.00"
    @State private var symbol = "building.columns.fill"
    @State private var rewards: [RewardRate] = []
    /// Only a sync ever set this before, so a card carried by hand could never be counted as
    /// one — no rates, and nothing owed on it anywhere in the app.
    @State private var isCard = false
    @State private var lookingUp = false
    @State private var lookupError: String?
    private var nameAvailable: Bool { !store.data.accounts.contains { $0.id != account?.id && $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame } }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Money.parse(opening) != nil && nameAvailable }
    var body: some View {
        NavigationStack {
            Form {
                Section("Account details") {
                    TextField("Account name", text: $name).accessibilityIdentifier("account-name")
                    TextField("Description", text: $detail)
                    Picker("Icon", selection: $symbol) {
                        Label("Bank", systemImage: "building.columns.fill").tag("building.columns.fill")
                        Label("Card", systemImage: "creditcard.fill").tag("creditcard.fill")
                        Label("Cash", systemImage: "banknote.fill").tag("banknote.fill")
                    }
                    Toggle("This is a credit card", isOn: $isCard).accessibilityIdentifier("account-is-card")
                }
                Section {
                    HStack { Text("$"); TextField("Opening balance", text: $opening).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("account-balance") }
                } header: { Text("Opening balance") } footer: { Text("Enter the balance before your earliest recorded transaction. Tracked balances then add income and subtract expenses. A negative opening balance is allowed.") }
                if isCard || !rewards.isEmpty { rewardsSection }
                if !nameAvailable { Text("Choose a unique account name so CSV imports can match it correctly.").foregroundStyle(Palette.orange) }
            }.scrollContentBackground(.hidden).pageBackground().navigationTitle(account == nil ? "Add an account" : "Edit account").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        guard let cents = Money.parse(opening) else { return }
                        // Edit what the user owns and leave the rest alone: rebuilding the account
                        // here would drop the institution it is matched to, and its rates with it.
                        var updated = account ?? BankAccount(name: "", detail: "", colorIndex: store.data.accounts.count % 3)
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.detail = detail
                        updated.symbol = symbol
                        updated.openingBalance = cents
                        updated.rewards = rewards.isEmpty ? nil : rewards
                        updated.isCreditCard = isCard
                        if store.saveAccount(updated) { dismiss() }
                    }.disabled(!valid).accessibilityIdentifier("save-account") }
                }
                .onAppear { if let account { name = account.name; detail = account.detail; opening = Money.input(account.openingBalance); symbol = account.symbol; rewards = account.rewards ?? []; isCard = account.isCreditCard == true || account.symbol == "creditcard.fill" } }
        }
    }

    /// What this card earns. Looked up for whatever card the bank reported, and editable after —
    /// published rates change, and the user is the one who knows which ones they actually have.
    private var rewardsSection: some View {
        Section {
            ForEach($rewards) { $rate in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Picker("", selection: $rate.category) {
                            Text("Everything else").tag(SpendingCategory?.none)
                            ForEach(SpendingCategory.allCases) { Text($0.rawValue).tag(SpendingCategory?.some($0)) }
                        }.labelsHidden()
                        Spacer()
                        TextField("0", value: Binding(get: { Double(rate.basisPoints) / 100 },
                                                      set: { rate.basisPoints = Int(($0 * 100).rounded()) }),
                                  format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 52)
                        Text("%").foregroundStyle(Palette.muted)
                    }
                    if let window = windowText(rate) {
                        Text(window).font(.system(size: 10)).foregroundStyle(rate.applies(on: Date()) ? Palette.muted : Palette.orange)
                    }
                    if !rate.note.isEmpty { Text(rate.note).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                }
            }.onDelete { rewards.remove(atOffsets: $0) }
            Button("Add a rate") { rewards.append(RewardRate(category: nil, basisPoints: 100)) }
            Button(lookingUp ? "Looking it up…" : "Look up published rates") {
                Task { await lookUp() }
            }.disabled(lookingUp).accessibilityIdentifier("lookup-rewards")
        } header: {
            Text(account?.officialName.map { "Rewards · \($0)" } ?? "Rewards")
        } footer: {
            Text(lookupError ?? "Rates are looked up from what the issuer publishes and can go out of date — a rotating category changes every quarter. Correct anything that's wrong; what you type here is what the app uses.")
                .foregroundStyle(lookupError == nil ? Palette.muted : Palette.orange)
        }
    }

    private func windowText(_ rate: RewardRate) -> String? {
        guard rate.startsOn != nil || rate.endsOn != nil else { return nil }
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        let from = rate.startsOn.map { $0.formatted(format) } ?? "now"
        let until = rate.endsOn.map { $0.formatted(format) } ?? "further notice"
        return rate.applies(on: Date()) ? "\(from) – \(until)" : "Not active · \(from) – \(until)"
    }

    private func lookUp() async {
        guard let account else { return }
        lookingUp = true; lookupError = nil
        defer { lookingUp = false }
        do {
            try await store.lookUpRewards(for: account)
            rewards = store.account(account.id)?.rewards ?? []
        } catch {
            lookupError = (error as? ImportError)?.errorDescription ?? error.localizedDescription
        }
    }
}
