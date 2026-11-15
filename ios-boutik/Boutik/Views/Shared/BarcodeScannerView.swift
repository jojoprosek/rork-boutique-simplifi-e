import SwiftUI
import AVFoundation

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onCode: (String) -> Void

    enum State { case checking, ready, denied, noCamera }
    @SwiftUI.State private var state: State = .checking
    @SwiftUI.State private var manualCode = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch state {
            case .checking:
                ProgressView().tint(.white)
            case .ready:
                ScannerPreview { code in
                    Haptics.success()
                    onCode(code)
                    dismiss()
                }
                .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 280, height: 170)
                    .shadow(color: .black.opacity(0.4), radius: 10)
            case .denied:
                message(icon: "camera.badge.ellipsis", title: "Caméra non autorisée",
                        text: "Autorisez la caméra pour scanner les codes-barres.") {
                    Button("Ouvrir les réglages") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(BigButtonStyle(kind: .green))
                }
            case .noCamera:
                message(icon: "camera.metering.unknown", title: "Aucune caméra disponible",
                        text: "Tapez le code-barres à la main.") { EmptyView() }
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(.white.opacity(0.18), in: .circle)
                    }
                    .accessibilityLabel("Fermer")
                    Spacer()
                }
                .padding()
                Spacer()
                HStack(spacing: 8) {
                    TextField("", text: $manualCode, prompt: Text("Ou tapez le code").foregroundStyle(.white.opacity(0.6)))
                        .keyboardType(.numberPad)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 50)
                        .background(.white.opacity(0.15), in: .capsule)
                    Button("OK") {
                        guard !manualCode.isEmpty else { return }
                        onCode(manualCode); dismiss()
                    }
                    .font(.headline).foregroundStyle(.white)
                    .frame(width: 64, height: 50).background(Color.gain, in: .capsule)
                }
                .padding()
            }
        }
        .task { await checkAccess() }
    }

    private func message<A: View>(icon: String, title: String, text: String, @ViewBuilder action: () -> A) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.white)
            Text(title).font(.title3.bold()).foregroundStyle(.white)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            action()
        }
        .padding(32)
    }

    private func checkAccess() async {
        guard ScannerPreview.findCamera() != nil else { state = .noCamera; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: state = .ready
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            state = ok ? .ready : .denied
        default: state = .denied
        }
    }
}

struct ScannerPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static func findCamera() -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(iOS 17.0, *) { types.append(.external) }
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        return session.devices.first { $0.position == .back } ?? session.devices.first
    }

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.onCode = onCode
        return c
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var done = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = ScannerPreview.findCamera(), let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .code39, .qr, .itf14]
            output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
        }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
            MainActor.assumeIsolated {
                guard !done, let code else { return }
                done = true
                onCode?(code)
            }
        }
    }
}
