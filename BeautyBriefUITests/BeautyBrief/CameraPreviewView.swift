import SwiftUI
import AVFoundation

// ─────────────────────────────────────────────
//  ScanMode  —  barcode scanner vs photo capture
// ─────────────────────────────────────────────

enum ScanMode: Sendable {
    case barcode
    case photo
}

// Explicit nonisolated conformances so ScanMode can be compared on any thread
// (e.g. inside CameraUIView.setMode's sessionQueue.async closure).
// Synthesised conformances on types used in @MainActor contexts can be inferred
// as @MainActor-isolated in Swift 5.10+, which produces a warning when the
// comparison is used from a nonisolated context.  A hand-written implementation
// in a plain extension is never actor-isolated.
extension ScanMode: Equatable {
    nonisolated static func == (lhs: ScanMode, rhs: ScanMode) -> Bool {
        switch (lhs, rhs) {
        case (.barcode, .barcode): return true
        case (.photo,   .photo):   return true
        default:                   return false
        }
    }
}
extension ScanMode: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        switch self {
        case .barcode: hasher.combine(0)
        case .photo:   hasher.combine(1)
        }
    }
}

// ─────────────────────────────────────────────
//  CameraPreviewView
//  Wraps AVCaptureSession in SwiftUI.
//  • Barcode mode: continuous live scanning, near-focus optimised
//  • Photo mode:  high-res AVCapturePhotoOutput triggered by triggerCapture
// ─────────────────────────────────────────────

struct CameraPreviewView: UIViewRepresentable {

    @Binding var mode: ScanMode
    @Binding var triggerCapture: Bool
    var onBarcodeDetected: (String) -> Void
    var onPhotoCaptured: (Data?) -> Void
    /// Called on the main thread once AVCaptureSession.startRunning() completes.
    var onSessionReady: (() -> Void)? = nil

    // CameraCoordinator is defined at the top level (see below) so it does NOT
    // inherit @MainActor from CameraPreviewView.  AVFoundation calls its delegate
    // methods from background threads, so it must be actor-free.
    typealias Coordinator = CameraCoordinator

    func makeCoordinator() -> CameraCoordinator {
        CameraCoordinator(onBarcodeDetected: onBarcodeDetected,
                          onPhotoCaptured: onPhotoCaptured)
    }

    func makeUIView(context: Context) -> CameraUIView {
        let view = CameraUIView()
        view.startSession(coordinator: context.coordinator, onReady: onSessionReady)
        return view
    }

    func updateUIView(_ uiView: CameraUIView, context: Context) {
        uiView.setMode(mode)
        if triggerCapture {
            uiView.triggerPhotoCapture()
            triggerCapture = false
        }
    }
}

// MARK: — CameraCoordinator
// Defined at the TOP LEVEL — not nested inside CameraPreviewView.
// SwiftUI Views are @MainActor; anything nested inside them inherits that
// isolation, which makes AVFoundation delegate conformances @MainActor-isolated.
// AVFoundation calls metadataOutput / photoOutput from background threads, so
// the coordinator must be free of any actor isolation.
// Moving it here (outside the @MainActor View) removes all inherited isolation.
final class CameraCoordinator: NSObject,
                               AVCaptureMetadataOutputObjectsDelegate,
                               AVCapturePhotoCaptureDelegate {

    let onBarcodeDetected: (String) -> Void
    let onPhotoCaptured: (Data?) -> Void
    private var lastDetected: String?
    private var lastDetectedAt: Date?

    init(onBarcodeDetected: @escaping (String) -> Void,
         onPhotoCaptured: @escaping (Data?) -> Void) {
        self.onBarcodeDetected = onBarcodeDetected
        self.onPhotoCaptured   = onPhotoCaptured
    }

    // Barcode scanned — fires on the dedicated metadata background queue
    // nonisolated: AVFoundation calls this from a background queue; the
    // method must not be actor-isolated or Swift 6 emits a conformance warning.
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput objects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let object = objects.first as? AVMetadataMachineReadableCodeObject,
              let value  = object.stringValue else { return }
        // Debounce — ignore same barcode within 2 seconds.
        // All property access must happen on the MainActor because the
        // AVFoundation delegate protocols are @MainActor-annotated in iOS 26.
        let now = Date()
        Task { @MainActor in
            if value == self.lastDetected,
               let last = self.lastDetectedAt,
               now.timeIntervalSince(last) < 2.0 { return }
            self.lastDetected   = value
            self.lastDetectedAt = now
            self.onBarcodeDetected(value)
        }
    }

    // High-res photo captured — fires on the session queue
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in self.onPhotoCaptured(data) }
    }
}

// MARK: — CameraUIView
final class CameraUIView: UIView {

    private var captureSession: AVCaptureSession?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private weak var coordinator: CameraCoordinator?

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    // Dedicated serial queue for all AVCaptureSession work.
    // Apple requires session configuration and startRunning() to happen off the main thread.
    // Running setup here prevents the 0.5–12 s stall that blocked the main thread previously.
    private static let sessionQueue = DispatchQueue(label: "com.beautybrief.session",
                                                    qos: .userInitiated)

    func startSession(coordinator: CameraCoordinator, onReady: (() -> Void)? = nil) {
        self.coordinator = coordinator

        // Return immediately — all heavy AVCapture work runs on the session queue.
        CameraUIView.sessionQueue.async { [weak self] in
            guard let self else { return }

            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .photo   // high-res preset for both modes

            // Prefer wide-angle rear camera
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video,
                                                 position: .back)
                      ?? AVCaptureDevice.default(for: .video)

            guard let device,
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            // Near-focus optimisation: restricts autofocus to close range (great for barcodes)
            try? device.lockForConfiguration()
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()

            // Metadata output — dedicated background queue for lowest latency
            let meta = AVCaptureMetadataOutput()
            if session.canAddOutput(meta) {
                session.addOutput(meta)
                let metaQueue = DispatchQueue(label: "com.beautybrief.metadata",
                                             qos: .userInteractive)
                meta.setMetadataObjectsDelegate(coordinator, queue: metaQueue)
                meta.metadataObjectTypes = [.ean13, .ean8, .upce, .code128, .qr, .dataMatrix]
            }

            // Photo output for high-res capture in photo mode
            let photo = AVCapturePhotoOutput()
            if session.canAddOutput(photo) {
                session.addOutput(photo)
            }

            session.commitConfiguration()

            // Wire up the preview layer on the main thread, then start running
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.videoPreviewLayer.session      = session
                self.videoPreviewLayer.videoGravity = .resizeAspectFill
                self.metadataOutput = meta
                self.photoOutput    = photo
                self.captureSession = session
            }

            // startRunning() is blocking — must stay off the main thread.
            // Notify the UI once the session is actually live.
            session.startRunning()
            DispatchQueue.main.async { onReady?() }
        }
    }

    // Enable/disable live barcode scanning based on mode
    func setMode(_ mode: ScanMode) {
        CameraUIView.sessionQueue.async { [weak self] in
            guard let meta = self?.metadataOutput else { return }
            meta.metadataObjectTypes = mode == .barcode
                ? [.ean13, .ean8, .upce, .code128, .qr, .dataMatrix]
                : []
        }
    }

    // Fire AVCapturePhotoOutput — result goes to coordinator delegate
    func triggerPhotoCapture() {
        guard let photoOutput, let coordinator else { return }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: coordinator)
    }

    func stopSession() {
        CameraUIView.sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }
}
