import SwiftUI
import LinkKit

struct ConnectBankView: View {
    var accountID: UUID
    var onImported: (ImportResult) -> Void
    @EnvironmentObject var store: FinanceStore
    @SwiftUI.Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case loadingToken
        case ready
        case presentingLink
        case exchanging
        case error(String)
    }

    @State private var phase: Phase = .loadingToken
    @State private var linkToken: String?
    @State private var linkSession: PlaidLinkSession?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                switch phase {
                case .loadingToken:
                    ProgressView().controlSize(.large)
                    Text("Getting ready…").font(.system(size: 14)).foregroundStyle(Palette.muted)
                case .ready, .presentingLink:
                    Image(systemName: "building.columns.fill").font(.system(size: 40, weight: .light)).frame(width: 94, height: 94).background(Palette.sage, in: Circle())
                    Text("Connect a bank").font(.system(size: 29, design: .serif))
                    Text("You’ll log into your bank on a screen run by Plaid. Your bank credentials never pass through this app.").font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(4).padding(.horizontal, 12)
                    PrimaryButton(title: "Continue", symbol: "arrow.right") { phase = .presentingLink }
                case .exchanging:
                    ProgressView().controlSize(.large)
                    Text("Linking your account…").font(.system(size: 14)).foregroundStyle(Palette.muted)
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34, weight: .light)).foregroundStyle(Palette.orange)
                    Text("Couldn’t connect").font(.system(size: 22, design: .serif))
                    Text(message).font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).padding(.horizontal, 12)
                    PrimaryButton(title: "Try again") { Task { await loadLinkToken() } }
                }
            }
            .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).pageBackground()
            .navigationTitle("Connect a bank").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await loadLinkToken() }
            .sheet(isPresented: Binding(get: { phase == .presentingLink }, set: { if !$0 && phase == .presentingLink { phase = .ready } })) {
                if let linkSession { linkSession.sheet() }
            }
        }
    }

    @MainActor private func loadLinkToken() async {
        phase = .loadingToken
        do {
            let token = try await PlaidService.createLinkToken()
            linkToken = token
            linkSession = try Plaid.createPlaidLinkSession(configuration: LinkTokenConfiguration(
                token: token,
                onSuccess: { success in Task { await handleSuccess(success) } },
                onExit: { exit in Task { await handleExit(exit) } },
                onEvent: nil,
                onLoad: nil
            ))
            phase = .ready
        } catch {
            phase = .error("Couldn’t start Plaid Link. Make sure the local backend is running (npm start in backend/), then try again.")
        }
    }

    @MainActor private func handleSuccess(_ success: LinkSuccess) async {
        phase = .exchanging
        do {
            try await PlaidService.exchangePublicToken(success.publicToken, institutionName: success.metadata.institution.name)
            let sync = try await PlaidService.fetchSync(accountID: accountID)
            store.apply(sync, addNew: false)
            onImported(ImportResult(transactions: sync.added, warnings: sync.added.isEmpty ? ["No new transactions were returned yet. Some banks take a moment after linking before transactions are available — try again shortly."] : []))
            dismiss()
        } catch {
            phase = .error((error as? ImportError)?.errorDescription ?? "Your bank connected, but we couldn’t finish syncing transactions. Try again from Import.")
        }
    }

    @MainActor private func handleExit(_ exit: LinkExit) async {
        if let error = exit.error {
            phase = .error(error.displayMessage ?? error.errorMessage)
        } else {
            phase = .ready
        }
    }
}
