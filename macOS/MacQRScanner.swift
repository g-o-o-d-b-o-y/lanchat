#if os(macOS)
import SwiftUI
@preconcurrency import AVFoundation
import Vision

struct MacQRScanner: NSViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeNSViewController(context: Context) -> CameraQRViewController {
        let vc = CameraQRViewController()
        vc.onCode = onCode
        return vc
    }

    func updateNSViewController(_ nsViewController: CameraQRViewController, context: Context) {}
}

/// Camera-based QR scanning built on `AVCaptureVideoDataOutput` + Vision's
/// `VNDetectBarcodesRequest`. Unlike `AVCaptureMetadataOutput`, this works
/// with any camera that streams frames — including Continuity Camera and
/// other CMIO extension devices that expose no QR metadata types.
final class CameraQRViewController: NSViewController {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var frameDelegate: CameraFrameDelegate?
    private let processingQueue = DispatchQueue(label: "LANChat.camera.processing")
    private var delivered = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if !configureCamera() {
            showUnavailableMessage()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        session.stopRunning()
    }

    private func configureCamera() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)

        let delegate = CameraFrameDelegate { [weak self] payload in
            guard let self else { return }
            DispatchQueue.main.async {
                self.deliver(payload)
            }
        }
        frameDelegate = delegate
        output.setSampleBufferDelegate(delegate, queue: processingQueue)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.wantsLayer = true
        view.layer?.addSublayer(layer)
        previewLayer = layer

        // startRunning() can block, so keep it off the main thread; capture
        // the session value locally so the @Sendable closure doesn't cross
        // actor isolation.
        let captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
        return true
    }

    private func deliver(_ payload: String) {
        guard !delivered else { return }
        delivered = true
        session.stopRunning()
        onCode?(payload)
    }

    private func showUnavailableMessage() {
        let label = NSTextField(labelWithString: "Camera unavailable.\nNo video capture device could be started on this Mac.")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: 14)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }
}

/// Receives frames on the processing queue and hands the first detected QR
/// payload to its callback. All mutable state lives on that one queue.
private final class CameraFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onDetected: (String) -> Void
    private let request: VNDetectBarcodesRequest
    private var delivered = false

    init(onDetected: @escaping (String) -> Void) {
        self.onDetected = onDetected
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        self.request = request
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !delivered,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard !delivered,
              let result = request.results?.first as? VNBarcodeObservation,
              let payload = result.payloadStringValue else { return }
        delivered = true
        onDetected(payload)
    }
}
#endif