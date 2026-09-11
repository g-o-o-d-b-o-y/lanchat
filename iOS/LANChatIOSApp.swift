#if os(iOS)
import SwiftUI

@main
struct LANChatIOSApp: App {
    @StateObject private var store = ChatStore(displayName: UIDevice.current.name)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ChatView(store: store)
                .tint(AppTheme.accent)
                .sheet(isPresented: $store.showingScanner) {
                    NavigationStack {
                        IOSQRScanner(
                            onCode: store.join(scannedValue:),
                            onCancel: { store.showingScanner = false }
                        )
                        .ignoresSafeArea()
                        .navigationTitle("Scan QR")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { store.showingScanner = false }
                            }
                        }
                    }
                }
                .sheet(isPresented: $store.showingQR) {
                    NavigationStack {
                        if let payload = store.qrPayload {
                            QRCodeView(value: payload)
                                .navigationTitle(qrSheetTitle)
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { store.showingQR = false }
                                    }
                                }
                        }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .onChange(of: scenePhase) { _, phase in
                    store.handleScenePhase(phase)
                }
        }
    }

    private var qrSheetTitle: String {
        if case .hosting = store.mode { return "Share this chat" }
        return "Join this chat"
    }
}
#endif