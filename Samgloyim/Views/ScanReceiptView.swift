import SwiftUI
import PhotosUI

/// Snap a receipt, read it on device, and map it to the card purchase it belongs to.
/// Anything the matcher can't place with confidence is mapped by the user, never guessed.
struct ScanReceiptView: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var reading: ReceiptReading?
    @State private var matches: [ReceiptMatch] = []
    @State private var chosenID: UUID?
    @State private var search = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showingCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var browsingAll = false
    @State private var attached: Transaction?

    private var suggestion: ReceiptMatch? { ReceiptMatcher.suggestion(from: matches) }
    private var chosen: Transaction? { store.receiptCandidates.first { $0.id == chosenID } }

    private var candidates: [Transaction] {
        let all = store.receiptCandidates
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        let needle = DuplicateDetector.normalized(query)
        return all.filter {
            DuplicateDetector.normalized($0.merchant).contains(needle) || Money.input($0.amount).contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let attached { success(attached) }
                    else if busy {
                        VStack(spacing: 22) {
                            ProgressView().controlSize(.large)
                            Text("Reading your receipt…").font(.headline)
                            Text("This happens on your device. The photo isn’t uploaded or stored.")
                                .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 90)
                    } else if reading != nil { mapping }
                    else { capture }
                }.padding(22)
            }
            .pageBackground()
            .navigationTitle(attached == nil ? (reading == nil ? "Scan a receipt" : "Match your receipt") : "Receipt matched")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(attached == nil ? "Cancel" : "Done") { dismiss() }.disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in Task { await scan(data) } }.ignoresSafeArea()
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    defer { libraryItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        error = "That image couldn’t be loaded."
                        return
                    }
                    await scan(data)
                }
            }
            .alert("Receipt needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "Try another photo.") }
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Snap it.\nWe’ll find the purchase.").font(.system(size: 34, design: .serif)).tracking(-0.7)
            Text("Take a photo of a receipt and we’ll match its total to a card purchase you’ve already synced. If we can’t place it, you pick the purchase yourself.")
                .font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(4)

            if CameraPicker.isAvailable {
                Button { showingCamera = true } label: {
                    option(symbol: "camera.fill", title: "Take a photo", detail: "Point at the receipt and capture", color: Palette.sage)
                }.buttonStyle(.plain).accessibilityIdentifier("scan-camera")
            }
            PhotosPicker(selection: $libraryItem, matching: .images) {
                option(symbol: "photo.on.rectangle", title: CameraPicker.isAvailable ? "Choose an existing photo" : "Choose a photo",
                       detail: CameraPicker.isAvailable ? "Use a receipt already in your library" : "No camera here — pick a receipt image",
                       color: Palette.peach)
            }.buttonStyle(.plain).accessibilityIdentifier("scan-library")

            if store.receiptCandidates.isEmpty {
                Label("No open card purchases yet. Sync a bank or add a transaction first, then a scanned receipt has something to attach to.",
                      systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).pocketCard(padding: 15)
            }
        }
    }

    private var mapping: some View {
        VStack(alignment: .leading, spacing: 20) {
            readingCard
            if let suggestion, !browsingAll {
                VStack(alignment: .leading, spacing: 12) {
                    Label("We found a match", systemImage: "sparkles").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.forest)
                    purchaseSummary(suggestion.transaction)
                    Text(suggestion.reasons.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.pocketCard()
                PrimaryButton(title: "Attach to this purchase", symbol: "paperclip") {
                    attach(to: suggestion.transaction, manual: false)
                }.accessibilityIdentifier("confirm-match")
                Button("Pick a different purchase") { browsingAll = true; chosenID = nil }
                    .font(.system(size: 13)).frame(maxWidth: .infinity)
            } else {
                manualMapping
            }
        }
    }

    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What we read").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.muted)
            Text(reading?.merchant ?? "Receipt").font(.system(size: 22, design: .serif))
            HStack(spacing: 14) {
                Text(reading?.amount.map { Money.format($0) } ?? "No total found")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(reading?.amount == nil ? Palette.orange : Palette.ink)
                Text(reading?.date?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "No date found")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            if reading?.amount == nil {
                Text("Without a total we can’t match this to a purchase. Choose the right one below.")
                    .font(.system(size: 11)).foregroundStyle(Palette.orange).lineSpacing(3)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pocketCard()
    }

    private var manualHeadline: (title: String, detail: String) {
        if matches.isEmpty {
            return ("No purchase matched this total.",
                    "Nothing in your transactions has this exact amount within a few days. Pick the purchase this receipt belongs to, or save it as a new one.")
        }
        if suggestion != nil {
            return ("Pick the right purchase.",
                    "Your choice replaces the one we suggested.")
        }
        return ("More than one purchase fits.",
                "Several purchases share this total. Pick the one this receipt belongs to.")
    }

    private var manualMapping: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(manualHeadline.title).font(.system(size: 17, weight: .semibold))
                Text(manualHeadline.detail).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
            }.pocketCard()

            if store.receiptCandidates.isEmpty {
                EmptyState(symbol: "tray", title: "No open purchases", detail: "Every purchase already has a receipt, or you haven’t added any yet.")
            } else {
                TextField("Search by merchant or amount", text: $search)
                    .textFieldStyle(.plain).font(.system(size: 14)).pocketCard(padding: 15)
                    .accessibilityIdentifier("purchase-search")
                ForEach(candidates) { transaction in
                    Button { chosenID = transaction.id } label: {
                        HStack(spacing: 10) {
                            Image(systemName: chosenID == transaction.id ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22)).foregroundStyle(chosenID == transaction.id ? Palette.forest : Palette.muted)
                            purchaseSummary(transaction)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).pocketCard(padding: 15)
                        .accessibilityLabel("Map receipt to \(transaction.merchant), \(Money.format(transaction.amount))")
                }
                if candidates.isEmpty {
                    Text("No purchase matches that search.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            }

            PrimaryButton(title: "Attach to selected purchase", symbol: "paperclip") {
                if let chosen { attach(to: chosen, manual: true) }
            }.disabled(chosen == nil).opacity(chosen == nil ? 0.45 : 1).accessibilityIdentifier("confirm-manual-match")

            if reading?.amount != nil {
                Button("None of these — save it as a new purchase") { saveAsNew() }
                    .font(.system(size: 13)).frame(maxWidth: .infinity).accessibilityIdentifier("save-as-new")
            }
        }
    }

    private func purchaseSummary(_ transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(transaction.merchant).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 6)
                Text(Money.format(transaction.amount)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
            }
            Text("\(transaction.date.formatted(.dateTime.month(.abbreviated).day())) · \(store.account(transaction.accountID)?.name ?? "Account") · \(transaction.source.rawValue)")
                .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func success(_ transaction: Transaction) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "paperclip").font(.system(size: 34, weight: .light)).frame(width: 94, height: 94).background(Palette.sage, in: Circle())
            Text("Matched.").font(.system(size: 36, design: .serif))
            Text("This receipt is now filed with \(transaction.merchant) · \(Money.format(transaction.amount)).")
                .font(.system(size: 15)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(4)
            PrimaryButton(title: "Scan another", symbol: "camera") { resetForNextScan() }
            Button("Back to my money") { dismiss() }.font(.system(size: 13))
        }.padding(.vertical, 50).frame(maxWidth: .infinity)
    }

    private func option(symbol: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).frame(width: 52, height: 58).background(color, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 11))
        }.pocketCard(padding: 15)
    }

    @MainActor private func scan(_ data: Data) async {
        guard data.count < 25_000_000 else {
            error = "That image is too large. Use a photo under 25 MB."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let result = try await ReceiptScanner.scan(data)
            let found = ReceiptMatcher.matches(for: result, in: store.data.transactions)
            reading = result
            matches = found
            chosenID = ReceiptMatcher.suggestion(from: found)?.id
            browsingAll = ReceiptMatcher.suggestion(from: found) == nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func attach(to transaction: Transaction, manual: Bool) {
        guard let reading else { return }
        let receipt = ReceiptAttachment(merchant: reading.merchant, total: reading.amount,
                                        purchasedAt: reading.date, text: reading.text, mappedManually: manual)
        guard store.attachReceipt(receipt, to: transaction.id) else {
            error = "That purchase couldn’t be updated. Please try again."
            return
        }
        var filed = transaction
        filed.receipt = receipt
        attached = filed
    }

    private func saveAsNew() {
        guard let reading, let total = reading.amount, total > 0,
              let accountID = store.selectedAccountID ?? store.data.accounts.first?.id else {
            error = "This receipt has no readable total, so it can only be attached to an existing purchase."
            return
        }
        var transaction = Transaction(merchant: reading.merchant, amount: total, date: reading.date ?? Date(),
                                      category: SpendingCategory.infer(from: reading.merchant), accountID: accountID,
                                      source: .receipt, note: "Receipt text:\n\(reading.text)")
        transaction.receipt = ReceiptAttachment(merchant: reading.merchant, total: total,
                                                purchasedAt: reading.date, text: reading.text, mappedManually: true)
        guard store.save(transaction) else {
            error = "That purchase couldn’t be saved. Check the merchant and total, then try again."
            return
        }
        attached = transaction
    }

    private func resetForNextScan() {
        reading = nil
        matches = []
        chosenID = nil
        search = ""
        browsingAll = false
        attached = nil
    }
}
