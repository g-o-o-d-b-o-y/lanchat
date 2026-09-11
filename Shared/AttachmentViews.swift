import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import QuickLook
#else
import AppKit
#endif

// MARK: - Data → Image

extension Image {
    init?(data: Data) {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #else
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #endif
    }
}

// MARK: - Attachment helpers

extension ChatWireMessage.Attachment {
    var data: Data? { Data(base64Encoded: dataBase64) }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var fileExtension: String {
        UTType(mimeType: mimeType)?.preferredFilenameExtension ?? "bin"
    }

    var iconName: String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.hasPrefix("audio/") { return "music.note" }
        return "doc"
    }

    /// Writes the payload to a temp file (needed for QuickLook / default-app
    /// previews) and returns its URL.
    func temporaryFileURL() -> URL? {
        guard let data else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LANChat-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Attachment card (shown inside a message bubble)

struct AttachmentCardView: View {
    let message: ChatWireMessage
    let isMine: Bool
    let onOpen: () -> Void

    var body: some View {
        if let attachment = message.attachment {
            if message.kind == .image, let data = attachment.data, let image = Image(data: data) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture(perform: onOpen)
            } else {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        Image(systemName: attachment.iconName)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.fileName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Text(attachment.sizeDescription)
                                .font(.caption2)
                                .foregroundStyle(isMine ? .white.opacity(0.8) : .secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.footnote)
                            .foregroundStyle(isMine ? .white.opacity(0.8) : .secondary)
                    }
                    .padding(12)
                    .background(
                        isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.13)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .foregroundStyle(isMine ? .white : .primary)
                }
                .buttonStyle(.plain)
                .help("Preview \(attachment.fileName)")
            }
        }
    }
}

// MARK: - Full-screen preview sheet

struct AttachmentPreviewSheet: View {
    let message: ChatWireMessage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if message.kind == .image,
                   let data = message.attachment?.data,
                   let image = Image(data: data) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .ignoresSafeArea()
                } else if let url = message.attachment?.temporaryFileURL() {
                    #if os(iOS)
                    QuickLookPreview(url: url)
                    #else
                    VStack(spacing: 14) {
                        ContentUnavailableView("Preview not available here", systemImage: "doc.viewfinder")
                        Button("Open in default app") {
                            NSWorkspace.shared.open(url)
                            dismiss()
                        }
                    }
                    #endif
                } else {
                    ContentUnavailableView("Preview unavailable", systemImage: "questionmark")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - QuickLook (iOS)

#if os(iOS)
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif