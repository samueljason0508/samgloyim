import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [PhotosPickerItem] = []
    @State private var filePicker = false
    @State private var receiptFiles = false
    @State private var accountID: UUID?
    @State private var busy = false
    @State private var progress = ""
    @State private var error: String?
    @State private var candidates: [Transaction] = []
    @State private var warnings: [String] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var reviewedIDs: Set<UUID> = []
    @State private var editing: Transaction?
    @State private var showingReview = false
    @State private var importedCount: Int?

    private var duplicateIDs: Set<UUID> {
        var previous: [Transaction] = [], ids: Set<UUID> = []
        for candidate in candidates {
            if store.duplicate(of: candidate, including: previous) != nil { ids.insert(candidate.id) }
            previous.append(candidate)
        }
        return ids
    }
    private var selected: [Transaction] { candidates.filter { selectedIDs.contains($0.id) } }
    private var canImport: Bool { !selected.isEmpty && selected.allSatisfy { $0.amount > 0 && ($0.source != .receipt || reviewedIDs.contains($0.id)) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let importedCount { success(importedCount) }
                    else if busy {
                        VStack(spacing: 22) { ProgressView().controlSize(.large); Text(progress).font(.headline); Text("Keep this screen open while we read your files.").font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical, 90)
                    } else if showingReview { review }
                    else { choices }
                }.padding(22)
            }.pageBackground().navigationTitle(importedCount == nil ? (showingReview ? "Review your import" : "Bring it all together") : "Import complete")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(importedCount == nil ? "Cancel" : "Done") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .onAppear { accountID = store.selectedAccountID ?? store.data.accounts.first?.id }
                .onChange(of: photos) { _, items in if !items.isEmpty { Task { await readPhotos(items) } } }
                .fileImporter(isPresented: $filePicker, allowedContentTypes: receiptFiles ? [.image] : [.commaSeparatedText, .plainText], allowsMultipleSelection: receiptFiles) { result in
                    switch result {
                    case .success(let urls): Task { await readFiles(urls) }
                    case .failure(let failure): error = failure.localizedDescription
                    }
                }
                .sheet(item: $editing) { transaction in
                    TransactionEditor(transaction: transaction) { updated in
                        if let index = candidates.firstIndex(where: { $0.id == updated.id }) { candidates[index] = updated }
                        reviewedIDs.insert(updated.id)
                        if duplicateIDs.contains(updated.id) { selectedIDs.remove(updated.id) }
                        else { selectedIDs.insert(updated.id) }
                    }
                }
                .alert("Import needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "Try another file.") }
        }
    }
    private var choices: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Less typing.\nMore perspective.").font(.system(size: 34, design: .serif)).tracking(-0.7)
            Text("Receipts and spreadsheets, in one clear picture. You’ll review everything before it’s added.").font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(4)
            VStack(alignment: .leading, spacing: 8) {
                Text("ADD TO ACCOUNT").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.muted)
                Picker("Default account", selection: $accountID) { ForEach(store.data.accounts) { Text($0.name).tag(Optional($0.id)) } }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
            }.pocketCard(padding: 15)
            PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .images) {
                importOption(symbol: "camera.viewfinder", title: "Receipt photos", detail: "Read up to 10 receipts from your library", color: Palette.sage)
            }.buttonStyle(.plain).accessibilityIdentifier("import-photos")
            Button { receiptFiles = true; filePicker = true } label: {
                importOption(symbol: "doc.viewfinder", title: "Receipts from Files", detail: "Choose images saved on your iPhone", color: Palette.peach)
            }.buttonStyle(.plain).accessibilityIdentifier("import-receipt-files")
            Button { receiptFiles = false; filePicker = true } label: {
                importOption(symbol: "tablecells", title: "Import a spreadsheet", detail: "CSV exports from Excel or Google Sheets", color: Color(hex: 0xE7E1ED))
            }.buttonStyle(.plain).accessibilityIdentifier("import-csv")
            VStack(alignment: .leading, spacing: 8) {
                Text("A simple CSV works best").font(.system(size: 13, weight: .semibold))
                Text("Required: date, merchant, amount\nOptional: category, account, kind, note").font(.system(size: 11, design: .monospaced)).lineSpacing(5).foregroundStyle(Palette.muted)
                Text("Dates: YYYY-MM-DD or MM/DD/YYYY. Amounts: USD. Rows are expenses unless kind is income. Export .xlsx files as CSV first.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)
            }.pocketCard(padding: 17)
            Button { sampleImport() } label: { Label("Try a sample import", systemImage: "sparkles").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity) }.padding(.vertical, 4).accessibilityIdentifier("sample-import")
            Text("Receipt reading happens on your device. Original images aren’t stored by the app. No bank connection is required.").font(.system(size: 11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }
    private func importOption(symbol: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).frame(width: 52, height: 58).background(color, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 15, weight: .semibold)); Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 11))
        }.pocketCard(padding: 15)
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("A quick second look.").font(.system(size: 29, design: .serif))
                Text("\(candidates.count) found · \(duplicateIDs.count) possible duplicate\(duplicateIDs.count == 1 ? "" : "s")").font(.system(size: 13, weight: .medium))
                Text("Possible duplicates start unchecked. Tap a row to edit it; use the circle to include or exclude it. Receipt readings must be opened and saved before importing.").font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
            }.pocketCard()
            if !warnings.isEmpty {
                DisclosureGroup("\(warnings.count) import note\(warnings.count == 1 ? "" : "s")") {
                    VStack(alignment: .leading, spacing: 8) { ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading) } }.padding(.top, 8)
                }.font(.system(size: 13)).foregroundStyle(Palette.orange).pocketCard(padding: 16)
            }
            ForEach(candidates) { transaction in
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        if selectedIDs.contains(transaction.id) { selectedIDs.remove(transaction.id) } else { selectedIDs.insert(transaction.id) }
                    } label: { Image(systemName: selectedIDs.contains(transaction.id) ? "checkmark.circle.fill" : "circle").font(.system(size: 23)).frame(width: 30, height: 44) }
                        .accessibilityLabel("\(selectedIDs.contains(transaction.id) ? "Exclude" : "Include") \(transaction.merchant)")
                    Button { editing = transaction } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(transaction.merchant).font(.system(size: 14, weight: .semibold)); Spacer(); Text(transaction.amount > 0 ? Money.format(transaction.amount) : "Add total").font(.system(size: 13, weight: .semibold)) }
                            Text("\(transaction.date.formatted(.dateTime.month(.abbreviated).day())) · \(transaction.category.rawValue)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            if duplicateIDs.contains(transaction.id) { Label("Possible duplicate", systemImage: "doc.on.doc").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.orange) }
                            if transaction.source == .receipt { Label(reviewedIDs.contains(transaction.id) ? "Reviewed" : "Tap to check the receipt reading", systemImage: reviewedIDs.contains(transaction.id) ? "checkmark" : "pencil").font(.system(size: 10)).foregroundStyle(reviewedIDs.contains(transaction.id) ? Palette.forest : Palette.orange) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.pocketCard(padding: 16)
            }
            PrimaryButton(title: "Import \(selected.count) transaction\(selected.count == 1 ? "" : "s")", symbol: "arrow.down.to.line") {
                if store.add(selected) { importedCount = selected.count }
            }.disabled(!canImport).opacity(canImport ? 1 : 0.45).accessibilityIdentifier("confirm-import")
            Button("Choose different files") { showingReview = false; candidates = []; photos = [] }.font(.system(size: 13)).frame(maxWidth: .infinity)
        }
    }
    private func success(_ count: Int) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark").font(.system(size: 35, weight: .light)).frame(width: 94, height: 94).background(Palette.sage, in: Circle())
            Text("All settled.").font(.system(size: 36, design: .serif))
            Text("\(count) transaction\(count == 1 ? " is" : "s are") now part of your picture. Your charts and budgets have been updated.").font(.system(size: 15)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(4)
            PrimaryButton(title: "Back to my money") { dismiss() }
        }.padding(.vertical, 50).frame(maxWidth: .infinity)
    }
    private func prepare(_ result: ImportResult) {
        candidates = result.transactions; warnings = result.warnings; reviewedIDs = []
        selectedIDs = Set(candidates.filter { $0.amount > 0 && !duplicateIDs.contains($0.id) }.map(\.id))
        showingReview = true
    }
    @MainActor private func readPhotos(_ items: [PhotosPickerItem]) async {
        guard let accountID else { return }
        busy = true; var transactions: [Transaction] = []; var notes: [String] = []
        defer { busy = false }
        for (index, item) in items.prefix(10).enumerated() {
            progress = "Reading receipt \(index + 1) of \(min(items.count, 10))…"
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw ImportError.message("The image couldn’t be loaded.") }
                guard data.count < 25_000_000 else { throw ImportError.message("Choose an image smaller than 25 MB.") }
                transactions.append(try await readReceipt(data, accountID: accountID))
            } catch { notes.append("Receipt \(index + 1): \(error.localizedDescription)") }
        }
        prepare(ImportResult(transactions: transactions, warnings: notes))
    }
    @MainActor private func readFiles(_ urls: [URL]) async {
        guard let accountID else { return }
        busy = true; progress = receiptFiles ? "Reading your receipts…" : "Reading your spreadsheet…"
        defer { busy = false }
        do {
            var transactions: [Transaction] = [], notes: [String] = []
            for url in urls.prefix(receiptFiles ? 10 : 1) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= (receiptFiles ? 25_000_000 : 5_000_000) else { throw ImportError.message("\(url.lastPathComponent) is too large. Use CSVs under 5 MB or images under 25 MB.") }
                let data = try Data(contentsOf: url)
                if receiptFiles {
                    do { transactions.append(try await readReceipt(data, accountID: accountID)) }
                    catch { notes.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                } else {
                    guard let text = String(data: data, encoding: .utf8) else { throw ImportError.message("Export your spreadsheet as UTF-8 CSV and try again.") }
                    let result = try CSVService.parse(text, accounts: store.data.accounts, defaultAccountID: accountID)
                    transactions += result.transactions; notes += result.warnings
                }
            }
            if urls.count > 10 { notes.append("Only the first 10 images were read. Import the remaining images separately.") }
            prepare(ImportResult(transactions: transactions, warnings: notes))
        } catch { self.error = error.localizedDescription }
    }
    private func readReceipt(_ data: Data, accountID: UUID) async throws -> Transaction {
        let reading = try await ReceiptScanner.scan(data)
        return Transaction(merchant: reading.merchant, amount: reading.amount ?? 0, date: reading.date ?? Date(), category: SpendingCategory.infer(from: reading.merchant), accountID: accountID, source: .receipt,
            note: "Review merchant, total, and date.\(reading.date == nil ? " No date found; today is a placeholder." : "")\n\nReceipt text:\n\(reading.text)")
    }
    private func sampleImport() {
        guard let accountID else { return }
        let existing = store.data.transactions.first { $0.accountID == accountID && $0.kind == .expense }
        var values = [Transaction(merchant: "Sample Campus Café", amount: 950, date: Date(), category: .food, accountID: accountID, source: .sample)]
        if var duplicate = existing { duplicate.id = UUID(); values.insert(duplicate, at: 0) }
        prepare(ImportResult(transactions: values, warnings: ["This is a sample import. Selected records will be saved if you continue."]))
    }
}
