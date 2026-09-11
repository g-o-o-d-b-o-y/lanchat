import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let value: String
    @State private var copied = false
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(spacing: 18) {
            Image(nsOrUiImage: makeImage())
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320, maxHeight: 320)

            Text("Scan this code from another device on the same Wi‑Fi network.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            VStack(spacing: 10) {
                Text(value)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Button {
                    copyToPasteboard()
                } label: {
                    Label(copied ? "Copied" : "Copy invitation link",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(28)
    }

    private func copyToPasteboard() {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func makeCIImage() -> CIImage {
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return CIImage.empty() }

        // The filter output has no quiet zone. Bake a white margin into the
        // image itself so the code stays scannable while the view can sit
        // directly on the sheet background — no white card behind it.
        let margin: CGFloat = 8
        let padded = output.transformed(by: CGAffineTransform(translationX: margin, y: margin))
        let canvas = CIImage(color: .white).cropped(to: padded.extent.insetBy(dx: -margin, dy: -margin))
        return padded.composited(over: canvas)
    }

    #if os(iOS)
    private func makeImage() -> UIImage {
        let image = makeCIImage().transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(image, from: image.extent) else { return UIImage() }
        return UIImage(cgImage: cg)
    }
    #else
    private func makeImage() -> NSImage {
        let image = makeCIImage().transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(image, from: image.extent) else { return NSImage() }
        return NSImage(cgImage: cg, size: .zero)
    }
    #endif
}

#if os(iOS)
private extension Image {
    init(nsOrUiImage: UIImage) { self.init(uiImage: nsOrUiImage) }
}
#else
private extension Image {
    init(nsOrUiImage: NSImage) { self.init(nsImage: nsOrUiImage) }
}
#endif
