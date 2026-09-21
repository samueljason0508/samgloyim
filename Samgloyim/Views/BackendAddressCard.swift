import SwiftUI

/// Where bank sync and card-rate lookup send their requests.
///
/// It lives on the import screen rather than in settings because it is only ever wrong in one
/// situation — the app running somewhere other than the machine holding the backend — and that is
/// the situation in which syncing fails and the user comes looking here.
struct BackendAddressCard: View {
    @AppStorage(PlaidService.addressKey) private var address = ""
    @State private var editing = false
    @State private var username = ""
    @State private var password = ""
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { editing.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.connected.to.line.below").font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SYNC SERVER").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.muted)
                        Text(PlaidService.baseURL.absoluteString).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: editing ? "chevron.up" : "chevron.down").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("backend-address-toggle")

            if editing {
                TextField("localhost:5100", text: $address)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(Palette.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("backend-address-field")
                // A name and a password, not the token itself: the token is a long string
                // nobody can type from memory, and signing in is how the backend hands it over.
                // Neither name nor password is kept — only what they buy, in the keychain.
                HStack(spacing: 8) {
                    TextField("Name", text: $username)
                        .font(.system(size: 12))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .background(Palette.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("backend-username-field")
                    SecureField("Password", text: $password)
                        .font(.system(size: 12))
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .background(Palette.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("backend-password-field")
                    if BackendCredential.token != nil {
                        Image(systemName: "checkmark.shield.fill").font(.system(size: 13)).foregroundStyle(Palette.forest)
                            .accessibilityLabel("Signed in")
                    }
                }
                HStack(spacing: 10) {
                    Button { Task { await check() } } label: {
                        Text(checking ? "Checking…" : (password.isEmpty ? "Check" : "Sign in")).font(.system(size: 11, weight: .semibold))
                    }.disabled(checking).accessibilityIdentifier("backend-check")
                    if !address.isEmpty {
                        Button("Use localhost") { address = ""; status = nil }.font(.system(size: 11))
                    }
                    if BackendCredential.token != nil {
                        Button("Sign out") { BackendCredential.store(""); password = ""; status = nil }
                            .font(.system(size: 11)).foregroundStyle(Palette.orange)
                    }
                }
                if let status {
                    Text(status).font(.system(size: 10)).foregroundStyle(status.hasPrefix("Reachable") ? Palette.forest : Palette.orange).lineSpacing(3)
                }
                // The one thing worth explaining, because it is the reason this field exists.
                Text("On this phone, “localhost” means the phone. Point this at the machine running the backend — its address on your network, or a public https address.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            }
        }.pocketCard(padding: 15)
    }

    private func check() async {
        checking = true
        defer { checking = false }
        if !password.isEmpty {
            guard await signIn() else { return }
        }
        status = await PlaidService.check()
    }

    /// Signing in is the only way a token gets here, so a failure to keep it is worth the
    /// same breath as a refused password: both leave the app unable to sync, for different
    /// reasons and with different fixes.
    private func signIn() async -> Bool {
        do {
            let token = try await PlaidService.logIn(username: username, password: password)
            guard BackendCredential.store(token) else {
                status = "Signed in, but this device’s keychain wouldn’t keep the token."
                return false
            }
            password = ""
            return true
        } catch {
            status = (error as? ImportError)?.errorDescription ?? "Couldn’t sign in."
            return false
        }
    }
}
