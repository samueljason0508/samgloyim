import SwiftUI

@main
struct SamgloyimApp: App {
    @StateObject private var store: FinanceStore
    @Environment(\.scenePhase) private var scenePhase
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let url = URL.applicationSupportDirectory.appendingPathComponent("SamgloyimUITests/finances.json")
            if !ProcessInfo.processInfo.arguments.contains("--keep-data") { try? FileManager.default.removeItem(at: url) }
            _store = StateObject(wrappedValue: FinanceStore(fileURL: url))
        } else {
            _store = StateObject(wrappedValue: FinanceStore(demo: false))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Palette.forest)
                .preferredColorScheme(.light)
                .alert("Couldn’t save your data", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button("OK") { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "Please try again.") }
                .task { if !isUITesting { await store.autoSyncPlaid() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && !isUITesting { Task { await store.autoSyncPlaid() } }
                }
        }
    }
}
