import SwiftUI
import AVFoundation

struct CameraScreen: View {
    @StateObject private var camera = CameraController()
    @State private var isoValue: Double = 100
    @State private var shutterValue: Double = 1.0 / 60.0
    @State private var selectedWB = "Neutral"
    @State private var readings: [String] = []

    private let shutters: [(String, Double)] = [
        ("1/15", 1.0/15.0), ("1/30", 1.0/30.0), ("1/60", 1.0/60.0),
        ("1/125", 1.0/125.0), ("1/250", 1.0/250.0)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack(alignment: .bottom) {
                        CameraPreview(session: camera.session)
                            .aspectRatio(3/4, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        Text(camera.status)
                            .font(.caption.weight(.semibold))
                            .padding(9)
                            .background(.black.opacity(0.65), in: Capsule())
                            .padding(12)
                    }

                    HStack {
                        metric("ISO", "(Int(isoValue))")
                        metric("Czas", shutters.first(where: { $0.1 == shutterValue })?.0 ?? "custom")
                        metric("WB", selectedWB)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("ISO"); Spacer(); Text("\(Int(isoValue))") }
                        Slider(value: $isoValue, in: Double(camera.minISO)...max(Double(camera.maxISO), Double(camera.minISO) + 1), step: 1)
                            .onChange(of: isoValue) { _, value in camera.setExposure(iso: Float(value), duration: shutterValue) }
                    }
                    .padding()
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Czas ekspozycji")
                        HStack {
                            ForEach(shutters, id: \.0) { item in
                                Button(item.0) {
                                    shutterValue = item.1
                                    camera.setExposure(iso: Float(isoValue), duration: item.1)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(shutterValue == item.1 ? .blue : .gray.opacity(0.35))
                            }
                        }
                    }
                    .padding()
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

                    HStack {
                        Button("Zablokuj ostrość") { camera.lockFocus() }
                        Button("Zablokuj WB") {
                            camera.lockWhiteBalance()
                            selectedWB = "Locked"
                        }
                    }
                    .buttonStyle(.bordered)

                    Button {
                        camera.captureMeasurement { result in
                            readings.insert(result, at: 0)
                        }
                    } label: {
                        Label("Zapisz pomiar", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)

                    if !readings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Pomiary").font(.headline)
                                Spacer()
                                Button("Eksport CSV") { exportCSV() }
                            }
                            ForEach(Array(readings.enumerated()), id: \.offset) { _, item in
                                Text(item).font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("TV Calibrator")
            .task { await camera.start() }
            .onDisappear { camera.stop() }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func exportCSV() {
        let csv = "Pomiar\n" + readings.reversed().joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tv-calibrator-measurements.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.keyWindow?.rootViewController?.present(activity, animated: true)
        } catch { camera.status = "Błąd eksportu" }
    }
}

@MainActor
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var status = "Inicjalizacja kamery…"
    @Published var minISO: Float = 25
    @Published var maxISO: Float = 800
    private let queue = DispatchQueue(label: "tv.calibrator.camera")
    private var device: AVCaptureDevice?
    private var output = AVCaptureVideoDataOutput()
    private var latestRGB = (r: 0.0, g: 0.0, b: 0.0, luma: 0.0)
    private let lock = NSLock()

    func start() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else { status = "Brak zgody na kamerę"; return }
        queue.async { [weak self] in self?.configure() }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            DispatchQueue.main.async { self.status = "Nie znaleziono tylnej kamery" }
            session.commitConfiguration()
            return
        }
        device = camera
        try? camera.lockForConfiguration()
        minISO = camera.activeFormat.minISO
        maxISO = camera.activeFormat.maxISO
        camera.unlockForConfiguration()
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async { self.status = "Kamera aktywna — ustaw wzorzec na TV" }
    }

    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func setExposure(iso: Float, duration: Double) {
        queue.async {
            guard let device = self.device, device.isExposureModeSupported(.custom) else { return }
            do {
                try device.lockForConfiguration()
                let d = CMTime(seconds: duration, preferredTimescale: 1_000_000_000)
                let clampedISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)
                device.setExposureModeCustom(duration: d, iso: clampedISO)
                device.unlockForConfiguration()
            } catch { DispatchQueue.main.async { self.status = "Nie można ustawić ekspozycji" } }
        }
    }

    func lockFocus() {
        queue.async {
            guard let d = self.device, d.isFocusModeSupported(.locked) else { return }
            try? d.lockForConfiguration()
            d.focusMode = .locked
            d.unlockForConfiguration()
            DispatchQueue.main.async { self.status = "Ostrość zablokowana" }
        }
    }

    func lockWhiteBalance() {
        queue.async {
            guard let d = self.device, d.isWhiteBalanceModeSupported(.locked) else { return }
            try? d.lockForConfiguration()
            let gains = d.deviceWhiteBalanceGains
            d.setWhiteBalanceModeLocked(with: gains)
            d.unlockForConfiguration()
            DispatchQueue.main.async { self.status = "Balans bieli zablokowany" }
        }
    }

    func captureMeasurement(completion: @escaping (String) -> Void) {
        lock.lock()
        let v = latestRGB
        lock.unlock()
        let line = String(format: "%@, R %.3f, G %.3f, B %.3f, Y %.3f", ISO8601DateFormatter().string(from: Date()), v.r, v.g, v.b, v.luma)
        completion(line)
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        let x0 = width / 3, x1 = width * 2 / 3, y0 = height / 3, y1 = height * 2 / 3
        for y in Swift.stride(from: y0, to: y1, by: 8) {
            for x in Swift.stride(from: x0, to: x1, by: 8) {
                let i = y * stride + x * 4
                b += Double(ptr[i]) / 255
                g += Double(ptr[i + 1]) / 255
                r += Double(ptr[i + 2]) / 255
                count += 1
            }
        }
        let rr = r / max(count, 1), gg = g / max(count, 1), bb = b / max(count, 1)
        let yy = 0.2126 * rr + 0.7152 * gg + 0.0722 * bb
        Task { @MainActor in
            self.lock.lock()
            self.latestRGB = (rr, gg, bb, yy)
            self.lock.unlock()
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.previewLayer.session = session }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
