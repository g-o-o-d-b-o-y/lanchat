#if os(macOS)
import SwiftUI

@main
struct LANChatMacApp: App {
    @StateObject private var store = ChatStore(displayName: Host.current().localizedName ?? "Mac")
    @State private var pasteDraft = ""
    @State private var pasteError: String?

    var body: some Scene {
        WindowGroup {
            ChatView(store: store)
                .tint(AppTheme.accent)
                .frame(minWidth: 620, minHeight: 620)
                .sheet(isPresented: $store.showingScanner) {
                    VStack(spacing: 0) {
                        SheetHeader(
                            title: "Scan QR",
                            subtitle: "Point the camera at an invitation QR code, or paste the link below."
                        ) {
                            store.showingScanner = false
                        }
                        Divider()
                        MacQRScanner(onCode: store.join(scannedValue:))
                            .frame(width: 640, height: 440)
                        Divider()
                        HStack(spacing: 8) {
                            TextField("Invitation link (lanchat://…)", text: $pasteDraft)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(joinViaPaste)
                            Button("Join", action: joinViaPaste)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(pasteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .keyboardShortcut(.defaultAction)
                        }
                        .padding()
                    }
                    .alert("LAN Chat", isPresented: Binding(
                        get: { pasteError != nil },
                        set: { if !$0 { pasteError = nil } }
                    )) {
                        Button("OK", role: .cancel) { pasteError = nil }
                    } message: {
                        Text(pasteError ?? "Unknown error")
                    }
                }
                .sheet(isPresented: $store.showingQR) {
                    VStack(spacing: 0) {
                        SheetHeader(
                            title: "Share this chat",
                            subtitle: "Scan this code from another device, or copy the invitation link."
                        ) {
                            store.showingQR = false
                        }
                        Divider()
                        if let payload = store.qrPayload {
                            QRCodeView(value: payload)
                        }
                    }
                    .frame(minWidth: 460, minHeight: 560)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 760, height: 700)
    }

    private func joinViaPaste() {
        let trimmed = pasteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try JoinQRCode.decode(trimmed)
            store.join(scannedValue: trimmed)
        } catch {
            pasteError = error.localizedDescription
        }
    }
}

private struct SheetHeader: View {
    let title: String
    let subtitle: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Label("Close", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
            .help("Close")
        }
        .padding()
    }
}
#endif