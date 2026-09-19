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
    enum ResetAction: String, Identifiable { case empty, demo; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 13) {
                        Image(systemName: "leaf.fill").font(.system(size: 27)).foregroundStyle(Palette.lime).frame(width: 60, height: 60).background(Palette.forest, in: RoundedRectangle(cornerRadius: 19))
                        VStack(alignment: .leading, spacing: 5) { Text("samgloyim").font(.system(size: 26, weight: .semibold, design: .rounded)); Text("A little clarity, every day.").font(.subheadline).foregroundStyle(Palette.muted) }
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
                    }
                    Button { accountRequest = AccountRequest(account: nil) } label: { Label("Add account", systemImage: "plus") }.accessibilityIdentifier("add-account")
                } header: { Text("Your accounts") } footer: { Text("Tracked balances = opening balance + all recorded income − all recorded expenses. These aren’t live bank balances.") }
                if !linkedBanks.isEmpty {
                    Section {
                        ForEach(linkedBanks) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "building.columns.fill").frame(width: 32).foregroundStyle(Palette.forest)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.institutionName).font(.system(size: 15, weight: .medium))
                                    Text("Read-only · connected \(formattedDate(item.linkedAt))").font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Button(role: .destructive) { Task { await disconnect(item) } } label: { Image(systemName: "trash") }
                            }.padding(.vertical, 5)
                        }
                    } header: { Text("Connected banks") } footer: { Text("Connections are read-only: this app can only see transactions, never move money. Disconnecting revokes access immediately.") }
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
                    feature("Clear spending insights", detail: "Charts and monthly notes use your recorded data. Lessons are written educational content; there’s no AI chatbot or live deal service.")
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
                }
                Section {
                    HStack { Text("$"); TextField("Opening balance", text: $opening).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("account-balance") }
                } header: { Text("Opening balance") } footer: { Text("Enter the balance before your earliest recorded transaction. Tracked balances then add income and subtract expenses. A negative opening balance is allowed.") }
                if !nameAvailable { Text("Choose a unique account name so CSV imports can match it correctly.").foregroundStyle(Palette.orange) }
            }.scrollContentBackground(.hidden).pageBackground().navigationTitle(account == nil ? "Add an account" : "Edit account").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        guard let cents = Money.parse(opening) else { return }
                        if store.saveAccount(BankAccount(id: account?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), detail: detail, symbol: symbol, openingBalance: cents, colorIndex: account?.colorIndex ?? store.data.accounts.count % 3)) { dismiss() }
                    }.disabled(!valid).accessibilityIdentifier("save-account") }
                }
                .onAppear { if let account { name = account.name; detail = account.detail; opening = Money.input(account.openingBalance); symbol = account.symbol } }
        }
    }
}
