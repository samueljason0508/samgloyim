import SwiftUI

struct TransactionEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    var transaction: Transaction?
    var onReviewSave: ((Transaction) -> Void)?
    @State private var merchant = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var category: SpendingCategory = .food
    @State private var kind: TransactionKind = .expense
    @State private var accountID: UUID?
    @State private var note = ""
    @State private var showDuplicate = false
    @State private var showDelete = false
    @State private var initialized = false

    /// A bank, CSV, or receipt row only ever had a calendar date. Offering a time field on one
    /// shows a meaningless 12:00 AM and invites setting a time the source never recorded.
    private var datePickerComponents: DatePickerComponents {
        guard let transaction else { return [.date, .hourAndMinute] }
        return transaction.recordedTime == nil ? [.date] : [.date, .hourAndMinute]
    }

    private var valid: Bool {
        !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (Money.parse(amount) ?? 0) > 0 && accountID != nil
    }
    private var draft: Transaction? {
        guard let cents = Money.parse(amount), cents > 0, let accountID else { return nil }
        return Transaction(id: transaction?.id ?? UUID(), merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), amount: cents,
            date: date, category: category, accountID: accountID, kind: kind, source: transaction?.source ?? .manual, note: note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) { ForEach(TransactionKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    HStack(alignment: .firstTextBaseline) {
                        Text("$").font(.system(size: 33, weight: .light)).foregroundStyle(Palette.muted)
                        TextField("0.00", text: $amount).font(.system(size: 43, weight: .regular, design: .rounded)).keyboardType(.decimalPad).accessibilityIdentifier("transaction-amount")
                    }.padding(.vertical, 10)
                    TextField(kind == .income ? "Where did it come from?" : "Where did you spend?", text: $merchant).textInputAutocapitalization(.words).accessibilityIdentifier("transaction-merchant")
                } header: { Text("The essentials") } footer: { Text("Amounts are in US dollars.") }
                Section("Details") {
                    DatePicker("Date", selection: $date, displayedComponents: datePickerComponents)
                    Picker("Account", selection: $accountID) {
                        ForEach(store.data.accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if kind == .expense { Picker("Category", selection: $category) { ForEach(SpendingCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } } }
                    TextField("Add a note (optional)", text: $note, axis: .vertical).lineLimit(2...6).accessibilityIdentifier("transaction-note")
                }
                if let transaction {
                    Section { LabeledContent("Added from", value: transaction.source.rawValue) }
                }
                if transaction != nil && onReviewSave == nil {
                    Section { Button("Delete transaction", role: .destructive) { showDelete = true }.accessibilityIdentifier("delete-transaction") }
                }
            }.scrollContentBackground(.hidden).pageBackground()
                .navigationTitle(onReviewSave != nil ? "Review transaction" : transaction == nil ? "Add transaction" : "Transaction details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { saveTapped() }.fontWeight(.semibold).disabled(!valid).accessibilityIdentifier("save-transaction") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
                }
                .onAppear {
                    guard !initialized else { return }; initialized = true
                    if let transaction {
                        merchant = transaction.merchant; amount = transaction.amount > 0 ? Money.input(transaction.amount) : ""; date = transaction.date
                        category = transaction.category; kind = transaction.kind; accountID = transaction.accountID; note = transaction.note
                    } else { accountID = store.cashAccountID }
                }
                .confirmationDialog("This looks like an existing transaction", isPresented: $showDuplicate, titleVisibility: .visible) {
                    Button("Save anyway") { commit() }
                    Button("Keep reviewing", role: .cancel) {}
                } message: { Text("The same account, merchant, date, and amount already exist. Saving will count this as a separate transaction.") }
                .confirmationDialog("Delete this transaction?", isPresented: $showDelete, titleVisibility: .visible) {
                    Button("Delete transaction", role: .destructive) { if let transaction, store.deleteTransaction(transaction.id) { dismiss() } }
                } message: { Text("This also updates your spending totals and account balance.") }
        }
    }
    private func saveTapped() {
        guard let draft else { return }
        if onReviewSave == nil && store.duplicate(of: draft) != nil { showDuplicate = true }
        else { commit() }
    }
    private func commit() {
        guard let draft else { return }
        if let onReviewSave { onReviewSave(draft); dismiss() }
        else if store.save(draft) { dismiss() }
    }
}
