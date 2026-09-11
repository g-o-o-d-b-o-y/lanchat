import Foundation
import SwiftUI

@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatWireMessage] = []
    @Published var status = "Not connected"
    @Published var mode: LANChatEngine.Mode = .idle
    @Published var errorText: String?
    @Published var qrPayload: String?
    @Published var showingQR = false
    @Published var showingScanner = false

    let localID = UUID()
    let displayName: String
    private let engine: LANChatEngine
    private var wasHostingBeforeBackground = false
    private var lastHostedServiceName: String?

    init(displayName: String) {
        self.displayName = displayName
        self.engine = LANChatEngine(localID: localID, displayName: displayName)

        engine.onMessage = { [weak self] message in
            Task { @MainActor in self?.messages.append(message) }
        }
        engine.onStatus = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        engine.onMode = { [weak self] mode in
            Task { @MainActor in self?.mode = mode }
        }
        engine.onError = { [weak self] error in
            Task { @MainActor in self?.errorText = error.localizedDescription }
        }
    }

    func hostAndShowQR() {
        // If we're already hosting, keep the running listener (and its
        // Bonjour registration) and just show the QR again. Recreating the
        // listener on every tap is wasteful and can briefly make the service
        // undiscoverable.
        let serviceName: String
        if case .hosting(let current) = mode {
            serviceName = current
        } else {
            serviceName = makeServiceName()
            engine.host(serviceName: serviceName)
        }
        do {
            qrPayload = try JoinQRCode(serviceName: serviceName, serviceType: LANChatEngine.serviceType).encode()
            showingQR = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// iOS suspends the app (and quietly invalidates the NWListener) when the
    /// device sleeps without delivering a state change. Tearing the engine
    /// down on background and re-hosting on return keeps the UI honest —
    /// otherwise the app believes it is still hosting while the Bonjour
    /// service is actually gone, and "Get QR" appears broken.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if case .hosting(let name) = mode {
                wasHostingBeforeBackground = true
                lastHostedServiceName = name
            }
            showingQR = false
            showingScanner = false
            engine.stop()
        case .active:
            if wasHostingBeforeBackground, let name = lastHostedServiceName {
                wasHostingBeforeBackground = false
                lastHostedServiceName = nil
                engine.host(serviceName: name)
            }
        default:
            break
        }
    }

    private func makeServiceName() -> String {
        "LANChat-\(String(localID.uuidString.prefix(6)))"
    }

    func join(scannedValue: String) {
        do {
            let invitation = try JoinQRCode.decode(scannedValue)
            showingScanner = false
            engine.join(invitation: invitation)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func send(_ text: String) {
        engine.send(text: text)
    }

    func sendMedia(data: Data, fileName: String, mimeType: String) {
        guard !data.isEmpty else { return }
        guard data.count <= ChatWireMessage.Attachment.maxSizeBytes else {
            errorText = "Attachments are limited to 15 MB per file."
            return
        }
        engine.send(attachment: ChatWireMessage.Attachment(
            fileName: fileName,
            mimeType: mimeType,
            fileSize: data.count,
            dataBase64: data.base64EncodedString()
        ))
    }

    func stop() {
        engine.stop()
    }
}
