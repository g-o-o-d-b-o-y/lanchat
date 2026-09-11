import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct ChatView: View {
    @ObservedObject var store: ChatStore
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showAttachOptions = false
    @State private var showPhotoPicker = false
    @State private var previewMessage: ChatWireMessage?

    private var isHosting: Bool {
        if case .hosting = store.mode { return true }
        return false
    }

    private var isJoining: Bool {
        if case .joining = store.mode { return true }
        return false
    }

    private var isChatActive: Bool {
        isHosting || store.mode == .connected
    }

    private var canSend: Bool {
        isChatActive && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messages
            #if os(iOS)
            Divider()
            #endif
            composer
        }
        .background(.background)
        .alert("LAN Chat", isPresented: Binding(
            get: { store.errorText != nil },
            set: { if !$0 { store.errorText = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorText = nil }
        } message: {
            Text(store.errorText ?? "Unknown error")
        }
        .sheet(item: $previewMessage) { message in
            AttachmentPreviewSheet(message: message)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImporter(result)
        }
        #if os(iOS)
        .confirmationDialog("Attach", isPresented: $showAttachOptions, titleVisibility: .visible) {
            Button("Photo or Video") { showPhotoPicker = true }
            Button("File") { showFileImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        // Programmatic PhotosPicker presentation (the picker can't be
        // embedded in menus/dialogs, so it lives here as a modifier).
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .any(of: [.images, .videos]))
        #endif
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    store.sendMedia(
                        data: data,
                        fileName: photoFileName(for: item),
                        mimeType: photoMIMEType(for: item)
                    )
                } catch {
                    store.errorText = error.localizedDescription
                }
            }
        }
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        Task { @MainActor in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    store.sendMedia(
                        data: data,
                        fileName: url.lastPathComponent,
                        mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                            ?? "application/octet-stream"
                    )
                } catch {
                    store.errorText = error.localizedDescription
                }
            case .failure(let error):
                store.errorText = error.localizedDescription
            }
        }
    }

    private func photoFileName(for item: PhotosPickerItem) -> String {
        guard let type = item.supportedContentTypes.first else { return "photo" }
        let base: String
        if type.conforms(to: .movie) { base = "video" }
        else if type.conforms(to: .image) { base = "photo" }
        else { base = "file" }
        return "\(base).\(type.preferredFilenameExtension ?? "bin")"
    }

    private func photoMIMEType(for item: PhotosPickerItem) -> String {
        if let type = item.supportedContentTypes.first, let mime = type.preferredMIMEType {
            return mime
        }
        if item.supportedContentTypes.first?.conforms(to: .movie) == true { return "video/quicktime" }
        return "application/octet-stream"
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                store.showingScanner = true
            } label: {
                Label("Scan QR", systemImage: "qrcode.viewfinder")
                    .collapsesToIconOnMobile()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isHosting)

            Spacer()

            VStack(spacing: 3) {
                Text("LAN Chat")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(store.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer()

            if isHosting {
                Button {
                    store.hostAndShowQR()
                } label: {
                    Label("Share QR", systemImage: "qrcode")
                        .collapsesToIconOnMobile()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Show the invitation QR code again")

                Button {
                    store.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .collapsesToIconOnMobile()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .help("Stop hosting this chat")
            } else {
                Button {
                    store.hostAndShowQR()
                } label: {
                    Label("Get QR", systemImage: "qrcode")
                        .collapsesToIconOnMobile()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isJoining)
                .help("Host this device and show an invitation QR code")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        switch store.mode {
        case .idle: .gray.opacity(0.5)
        case .joining: .orange
        case .hosting: .green
        case .connected: AppTheme.accent
        }
    }

    // MARK: - Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.messages.isEmpty {
                        ContentUnavailableView(
                            "No messages yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Create a QR invite or scan one to join a chat.")
                        )
                        .padding(.top, 80)
                    }

                    ForEach(store.messages) { message in
                        MessageBubble(
                            message: message,
                            isMine: message.senderID == store.localID,
                            onOpenAttachment: { previewMessage = message }
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: store.messages.count) { _, _ in
                if let last = store.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // One unified attach button:
            // - iOS: action sheet → "Photo or Video" (Photos picker) | "File"
            // - macOS: the file open panel directly (covers files + images)
            Button {
                #if os(iOS)
                showAttachOptions = true
                #else
                showFileImporter = true
                #endif
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(.secondary.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isChatActive)
            .opacity(isChatActive ? 1 : 0.35)
            .help("Attach a photo, video, or document")

            TextField(composerPlaceholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 40)
                .background(fieldFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(fieldStroke, lineWidth: 1.2)
                }
                .onSubmit(send)
                .disabled(!isChatActive)

            // Fixed 40×40 circle so the send button always matches the
            // single-line height of the input field (native control sizes
            // render larger than the field on iOS and smaller on macOS).
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.white)
                    .background(.tint, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.35)
            .help("Send message")
        }
        .padding()
        #if os(iOS)
        .background(.background)
        #else
        .background(.bar)
        #endif
    }

    /// On iOS the composer sits flush on the page background — just a hairline
    /// divider above it. macOS keeps the material bar for visual separation.
    private var fieldFill: Color {
        #if os(iOS)
        Color.clear
        #else
        Color.secondary.opacity(0.10)
        #endif
    }

    private var fieldStroke: AnyShapeStyle {
        if composerFocused {
            return AnyShapeStyle(.tint)
        }
        #if os(iOS)
        return AnyShapeStyle(Color.secondary.opacity(0.25))
        #else
        return AnyShapeStyle(.clear)
        #endif
    }

    private var composerPlaceholder: String {
        if isChatActive { return "Message" }
        if isJoining { return "Connecting to a chat…" }
        return "Start or join a chat to send messages"
    }

    private func send() {
        let value = draft
        draft = ""
        composerFocused = false
        store.send(value)
    }
}

private struct MessageBubble: View {
    let message: ChatWireMessage
    let isMine: Bool
    let onOpenAttachment: () -> Void

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 60) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if message.kind == .system {
                    Text(message.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                } else {
                    HStack(spacing: 6) {
                        Text(message.senderName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(message.sentAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if message.attachment != nil {
                        AttachmentCardView(message: message, isMine: isMine, onOpen: onOpenAttachment)
                            .frame(maxWidth: 300)
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .textSelection(.enabled)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.13)),
                                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                            )
                            .foregroundStyle(isMine ? .white : .primary)
                    }
                }
            }
            if !isMine { Spacer(minLength: 60) }
        }
    }
}

private extension View {
    /// Header buttons become icon-only on iPhone; macOS and iPad keep labels.
    @ViewBuilder
    func collapsesToIconOnMobile() -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            labelStyle(.iconOnly)
        } else {
            self
        }
        #else
        self
        #endif
    }
}