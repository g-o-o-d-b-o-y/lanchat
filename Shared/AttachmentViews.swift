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
        // Trust the original file name over MIME mapping — MIME-to-UTType
        // lookups for generic types (application/octet-stream, markdown…)
        // produce nil/".bin" where the real extension is perfectly usable.
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? "bin" : ext
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
                    .frame(maxWidth: 240, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2.weight(.bold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    ZStack {
                        Color.black.ignoresSafeArea()
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(.vertical, 8)
                    }
                    .overlay(alignment: .bottom) {
                        if let attachment = message.attachment {
                            VStack(spacing: 2) {
                                Text(attachment.fileName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)
                                Text(attachment.sizeDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.bottom, 12)
                        }
                    }
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