import SwiftUI

/// Where bank sync and card-rate lookup send their requests.
///
/// It lives on the import screen rather than in settings because it is only ever wrong in one
/// situation — the app running somewhere other than the machine holding the backend — and that is
/// the situation in which syncing fails and the user comes looking here.
struct BackendAddressCard: View {
    @AppStorage(PlaidService.addressKey) private var address = ""
    @State private var editing = false
    @State private var token = ""
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { if editing { save() }; withAnimation(.easeInOut(duration: 0.2)) { editing.toggle() } } label: {
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
                // The token is not shown back: it is stored in the keychain, and a field that
                // reprints a secret on screen has no reason to.
                HStack(spacing: 8) {
                    SecureField(BackendCredential.token == nil ? "Access token" : "Stored — type to replace", text: $token)
                        .font(.system(size: 12, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .background(Palette.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("backend-token-field")
                    if BackendCredential.token != nil {
                        Image(systemName: "checkmark.shield.fill").font(.system(size: 13)).foregroundStyle(Palette.forest)
                            .accessibilityLabel("A token is stored")
                    }
                }
                HStack(spacing: 10) {
                    Button { Task { await check() } } label: {
                        Text(checking ? "Checking…" : "Check").font(.system(size: 11, weight: .semibold))
                    }.disabled(checking).accessibilityIdentifier("backend-check")
                    if !address.isEmpty {
                        Button("Use localhost") { address = ""; status = nil }.font(.system(size: 11))
                    }
                    if BackendCredential.token != nil {
                        Button("Forget token") { BackendCredential.store(""); token = ""; status = nil }
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
        save()
        checking = true
        defer { checking = false }
        status = await PlaidService.check()
    }

    /// A token typed but never checked is still a token the user meant to set.
    ///
    /// A keychain that refuses the write leaves the app looking like the backend rejected it,
    /// which sends the user off fixing the wrong thing — so say which one happened.
    private func save() {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if BackendCredential.store(token) {
            token = ""
        } else {
            status = "Couldn’t save the token to this device’s keychain, so it wasn’t kept."
        }
    }
}
