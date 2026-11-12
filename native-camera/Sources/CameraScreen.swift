import SwiftUI
import AVFoundation
import UIKit

private enum TVPattern: String, CaseIterable, Identifiable {
    case gray = "Szarość 50%"
    case black = "Czerń"
    case pluge = "PLUGE"
    case white = "Biel"
    case grayscale = "Skala szarości"
    case rgb = "Podstawowe RGB"
    case bars = "Pasy kolorów"
    var id: String { rawValue }
    var instruction: String {
        switch self {
        case .gray: return "Jednolita plansza 50% szarości. Służy do sprawdzenia stabilności odczytu i nierównomierności."
        case .black: return "Czarna plansza. Sprawdź, czy ekran nie świeci szarością i czy detale w cieniu nie znikają."
        case .pluge: return "PLUGE. Dostosuj poziom czerni tak, aby najciemniejszy element był niewidoczny, a sąsiedni ciemny element ledwo widoczny."
        case .white: return "Biała plansza. Sprawdź clipping i czy biel nie zmienia koloru. Kamera nie mierzy tu nitów."
        case .grayscale: return "Stopnie szarości. Sprawdź płynność przejść, zafarby i utratę detali."
        case .rgb: return "Czerwony, zielony i niebieski. To test kanałów, nie podstawa do ręcznego CMS."
        case .bars: return "Pasy kolorów. Oceniaj clipping, banding i wyraźne odchylenia."
        }
    }
}

private struct Reading: Identifiable {
    let id = UUID()
    let date: Date
    let pattern: String
    let red: Double
    let green: Double
    let blue: Double
    let luma: Double
    let spread: Double
    let clipping: Double
    let temporalVariation: Double
    let sampleCount: Int
    var csv: String {
        String(format: "%@,%@,%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%d",
               ISO8601DateFormatter().string(from: date), pattern, red, green, blue, luma, spread, clipping, temporalVariation, sampleCount)
    }
}

struct CameraScreen: View {
    @StateObject private var camera = CameraController()
    @State private var selectedPattern: TVPattern = .gray
    @State private var isCapturing = false
    @State private var isoValue: Double = 100
    @State private var shutterValue: Double = 1.0 / 60.0
    @State private var focusLocked = false
    @State private var wbLocked = false
    @State private var readings: [Reading] = []
    @State private var activeTab = 0
    @State private var showExport = false
    @State private var exportURL: URL?
    @State private var showGuideDetails = false

    private let shutters: [(String, Double)] = [
        ("1/15", 1.0/15.0), ("1/30", 1.0/30.0), ("1/60", 1.0/60.0),
        ("1/125", 1.0/125.0), ("1/250", 1.0/250.0)
    ]

    var body: some View {
        TabView(selection: $activeTab) {
            dashboard.tag(0).tabItem { Label("Start", systemImage: "viewfinder") }
            measurement.tag(1).tabItem { Label("Pomiar", systemImage: "scope") }
            report.tag(2).tabItem { Label("Wyniki", systemImage: "chart.bar.xaxis") }
            guide.tag(3).tabItem { Label("Ustawienia TV", systemImage: "slider.horizontal.3") }
        }
        .preferredColorScheme(.dark)
        .tint(.cyan)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $showExport) {
            if let url = exportURL { ShareSheet(items: [url]) }
        }
    }

    private var dashboard: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TV CALIBRATOR").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(.cyan)
                        Text("Diagnostyka obrazu").font(.largeTitle.bold())
                        Text("Samsung UE55TU7002KXXH · PS5").foregroundStyle(.secondary)
                    }
                    cameraCard
                    HStack(spacing: 10) {
                        statusTile("KAMERA", camera.status, icon: "camera")
                        statusTile("ODCZYT", camera.hasReading ? "Aktywny" : "Oczekiwanie", icon: "waveform.path")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Następny krok", systemImage: "flag.fill").font(.headline)
                        Text("Zacznij od SDR. Ustaw na PS5 wyjście SDR, uruchom planszę 50% Gray na telewizorze i sprawdź powtarzalność pięciu pomiarów.")
                            .foregroundStyle(.secondary)
                        Button { activeTab = 1 } label: {
                            Label("Rozpocznij test", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                    }.padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    disclaimer
                }.padding()
            }.navigationBarTitleDisplayMode(.inline)
        }
    }

    private var measurement: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sesja pomiarowa").font(.largeTitle.bold())
                    cameraCard
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wzorzec wyświetlany na TV").font(.headline)
                        Picker("Wzorzec", selection: $selectedPattern) {
                            ForEach(TVPattern.allCases) { p in Text(p.rawValue).tag(p) }
                        }.pickerStyle(.menu).tint(.cyan)
                        .onChange(of: selectedPattern) { _ in camera.resetSampleBuffer() }
                        Text(selectedPattern.instruction).font(.subheadline).foregroundStyle(.secondary)
                        Text("Pamiętaj: ten wybór opisuje pomiar. Planszę wyświetlasz na TV przez odtwarzacz wzorców PWA.")
                            .font(.caption).foregroundStyle(.orange)
                    }.padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    liveMetrics
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Ekspozycja").font(.headline); Spacer(); Text("ISO \(Int(isoValue))").monospacedDigit().foregroundStyle(.cyan) }
                        Slider(value: $isoValue, in: Double(camera.minISO)...max(Double(camera.maxISO), Double(camera.minISO)+1), step: 1)
                            .onChange(of: isoValue) { value in camera.setExposure(iso: Float(value), duration: shutterValue) }
                        Text("Czas naświetlania").font(.subheadline.weight(.semibold))
                        HStack {
                            ForEach(shutters, id: \.0) { item in
                                Button(item.0) {
                                    shutterValue = item.1
                                    camera.setExposure(iso: Float(isoValue), duration: item.1)
                                }
                                .font(.caption.bold())
                                .buttonStyle(.bordered)
                                .tint(shutterValue == item.1 ? .cyan : .gray)
                            }
                        }
                    }.padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Button {
                            camera.lockFocus(); focusLocked = true
                        } label: { Label(focusLocked ? "Ostrość OK" : "Zablokuj ostrość", systemImage: "viewfinder") }
                            .buttonStyle(.bordered).tint(focusLocked ? .green : .cyan)
                        Button {
                            camera.lockWhiteBalance(); wbLocked = true
                        } label: { Label(wbLocked ? "WB OK" : "Zablokuj WB", systemImage: "sun.max") }
                            .buttonStyle(.bordered).tint(wbLocked ? .green : .cyan)
                    }
                    Button {
                        isCapturing = true
                        camera.captureMeasurement { sample in
                            readings.insert(Reading(date: Date(), pattern: selectedPattern.rawValue, red: sample.r, green: sample.g, blue: sample.b, luma: sample.luma, spread: sample.spread, clipping: sample.clipping, temporalVariation: sample.temporalVariation, sampleCount: Int(sample.sampleCount)), at: 0)
                            isCapturing = false
                            activeTab = 2
                        }
                    } label: {
                        Label(isCapturing ? "STABILIZUJĘ OBRAZ…" : "ZAPISZ POMIAR", systemImage: "scope")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
                    }.buttonStyle(.borderedProminent).disabled(!camera.hasReading || isCapturing)
                    Text("Wykonaj co najmniej 5 odczytów tego samego wzorca bez zmiany ustawień. Dopiero wtedy ocenimy stabilność.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.navigationBarTitleDisplayMode(.inline)
        }
    }

    private var report: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Wyniki sesji").font(.largeTitle.bold())
                    if readings.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar").font(.system(size: 42)).foregroundStyle(.secondary)
                            Text("Brak pomiarów").font(.headline)
                            Text("Przejdź do zakładki Pomiar i zapisz pierwszy odczyt.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 48)
                    } else {
                        let avg = averageReading
                        HStack(spacing: 10) {
                            resultTile("POMIARY", "\(readings.count)")
                            resultTile("ŚREDNIA Y", String(format: "%.3f", avg.luma))
                            resultTile("ROZPIĘTOŚĆ", String(format: "%.3f", avg.spread))
                            resultTile("CLIPPING", String(format: "%.1f%%", avg.clipping * 100))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ostatnie odczyty").font(.headline)
                            ForEach(readings.prefix(30)) { r in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(r.pattern).font(.subheadline.weight(.semibold))
                                        Text(r.date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(String(format: "R %.2f  G %.2f  B %.2f  ·  clip %.1f%% · CV %.2f%%", r.red, r.green, r.blue, r.clipping * 100, r.temporalVariation * 100))
                                        .font(.system(.caption2, design: .monospaced))
                                }.padding(10).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Button { exportReadings() } label: {
                            Label("Eksportuj CSV", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button(role: .destructive) { readings.removeAll() } label: {
                            Label("Wyczyść sesję", systemImage: "trash").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                        Text("Interpretacja: wartości RGB/Y pochodzą z przetworzonego obrazu kamery. Nadają się do porównywania powtórzeń w niezmienionych warunkach, nie do wyliczania Delta E, nitów ani korekt balansu bieli.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding()
            }.navigationBarTitleDisplayMode(.inline)
        }
    }

    private var guide: some View {
        NavigationStack {
            List {
                Section("Profil: PS5 · SDR") {
                    setting("Tryb obrazu", "Gra", "Włącz Tryb Gry dla wejścia HDMI z PS5. Telewizor może automatycznie przełączyć tryb obrazu na Gra.")
                    setting("Jasność / podświetlenie", "Dobierz do pomieszczenia", "Nie używaj kamery iPhone'a do ustawiania nitów. Ustaw komfortową jasność bez utraty detali.")
                    setting("Kontrast", "Punkt wyjścia: ustawienie fabryczne", "Dopiero planszą clipping sprawdzaj, czy jasne stopnie nie zlewają się w biel.")
                    setting("Ostrość", "Nisko, bez obwódek", "Użyj wzorca ostrych krawędzi. Nie podbijaj ostrości, jeśli pojawiają się jasne kontury.")
                    setting("Ton kolorów", "Ciepły / Warm2 jeśli dostępny", "To punkt wyjścia do naturalnej bieli, nie wynik pomiaru konkretnego egzemplarza.")
                    setting("Kontrast dynamiczny", "Wyłącz", "Wyłącz dynamiczne przetwarzanie na czas testów, żeby pomiary nie pływały.")
                    setting("Przestrzeń kolorów", "Auto", "Nie ustawiaj Native ani Custom bez wiarygodnego pomiaru gamutu.")
                    setting("Ustawienia obrazu", "Zapisz osobno dla źródła", "Samsung może przechowywać ustawienia osobno dla wejść i trybów obrazu.")
                }
                Section("PS5 · sygnał") {
                    setting("Rozdzielczość", "Automatycznie / 2160p", "Pozwól konsoli i telewizorowi uzgodnić 4K.")
                    setting("HDR", "Włączaj tylko dla treści HDR", "Wykonaj osobną kalibrację HDR w ustawieniach PS5 po zakończeniu SDR.")
                    setting("Zakres RGB", "Automatycznie", "Nie wymuszaj Limited/Full bez potwierdzenia zgodności całego toru HDMI.")
                    setting("ALLM / Tryb Gry", "Automatycznie / Włączony", "Priorytetem jest niski input lag.")
                }
                Section("Procedura") {
                    Label("1. Najpierw SDR i tryb Gra.", systemImage: "1.circle")
                    Label("2. Wyłącz ulepszacze obrazu.", systemImage: "2.circle")
                    Label("3. Ustaw poziom czerni planszą PLUGE.", systemImage: "3.circle")
                    Label("4. Sprawdź clipping bieli i skalę szarości.", systemImage: "4.circle")
                    Label("5. Zapisz 5 odczytów szarości i oceń powtarzalność.", systemImage: "5.circle")
                    Label("6. Dopiero potem przejdź do HDR.", systemImage: "6.circle")
                }
                Section("Ważne") { disclaimer }
            }
            .navigationTitle("Przewodnik")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var cameraCard: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: camera.session)
                .frame(height: 245)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.cyan.opacity(0.9), lineWidth: 1.5)
                            .frame(width: geo.size.width * 0.34, height: geo.size.height * 0.34)
                            .position(x: geo.size.width/2, y: geo.size.height/2)
                    }.allowsHitTesting(false)
                }
            Text(camera.status)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.72), in: Capsule()).padding(10)
        }
    }

    private var liveMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Odczyt na żywo · centralny obszar").font(.headline)
            HStack {
                metric("R", camera.live.r)
                metric("G", camera.live.g)
                metric("B", camera.live.b)
                metric("Y linear", camera.live.luma)
                metric("Clip", camera.live.clipping * 100)
            }
            HStack {
                Text("Rozrzut w obszarze")
                Spacer()
                Text(String(format: "%.3f", camera.live.spread)).monospacedDigit().foregroundStyle(.cyan)
            }.font(.caption)
            Text("To odczyt względny z klatki kamery, nie pomiar światła emitowanego przez panel.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var disclaimer: some View {
        Text("Uwaga: iPhone nie jest kolorymetrem. Automatyczne przetwarzanie obrazu, odbicia, kąt i charakterystyka sensora ograniczają dokładność. Aplikacja nie będzie wymyślać wartości balansu bieli, gammy ani jasności w nitach. Do certyfikowanej kalibracji potrzebna jest sonda.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private var averageReading: Reading {
        let n = Double(readings.count)
        return Reading(date: Date(), pattern: "Średnia", red: readings.map(\.red).reduce(0,+)/n,
                       green: readings.map(\.green).reduce(0,+)/n, blue: readings.map(\.blue).reduce(0,+)/n,
                       luma: readings.map(\.luma).reduce(0,+)/n, spread: readings.map(\.spread).reduce(0,+)/n,
                       clipping: readings.map(\.clipping).reduce(0,+)/n,
                       temporalVariation: readings.map(\.temporalVariation).reduce(0,+)/n,
                       sampleCount: Int((readings.map { Double($0.sampleCount) }.reduce(0,+)/n).rounded()))
    }

    private func metric(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(String(format: "%.3f", value)).font(.system(.headline, design: .monospaced))
        }.frame(maxWidth: .infinity).padding(.vertical, 10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusTile(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func resultTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func setting(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value).font(.subheadline).foregroundStyle(.cyan).multilineTextAlignment(.trailing)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }

    private func exportReadings() {
        let header = "timestamp,pattern,red,green,blue,linear_luma,spatial_luma_stddev,clipped_pixel_fraction,temporal_luma_cv,sample_count"
        let csv = ([header] + readings.reversed().map(\.csv)).joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tv-calibrator-session.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showExport = true
        } catch { camera.setStatus("Nie udało się wyeksportować CSV") }
    }
}

private final class CameraController: NSObject, ObservableObject {
    struct Sample {
        var r = 0.0; var g = 0.0; var b = 0.0; var luma = 0.0; var spread = 0.0
        var clipping = 0.0
        var pixelCount = 0.0
        var temporalVariation = 0.0
        var sampleCount = 0.0
    }
    let session = AVCaptureSession()
    @Published var status = "Oczekiwanie na kamerę"
    @Published var minISO: Float = 25
    @Published var maxISO: Float = 800
    @Published var live = Sample()
    @Published var hasReading = false
    private let queue = DispatchQueue(label: "tv.calibrator.capture")
    private var device: AVCaptureDevice?
    private let output = AVCaptureVideoDataOutput()
    private let lock = NSLock()
    private var latest = Sample()
    private var recentSamples: [Sample] = []
    private var frameCounter = 0

    func start() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else { setStatus("Brak dostępu do kamery"); return }
        queue.async { [weak self] in self?.configure() }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: d), session.canAddInput(input) else {
            session.commitConfiguration()
            setStatus("Nie znaleziono tylnej kamery")
            return
        }
        device = d
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        do {
            try d.lockForConfiguration()
            DispatchQueue.main.async {
                self.minISO = d.activeFormat.minISO
                self.maxISO = d.activeFormat.maxISO
                self.status = "Kamera aktywna"
            }
            d.unlockForConfiguration()
        } catch { setStatus("Nie można skonfigurować kamery") }
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func setStatus(_ value: String) { DispatchQueue.main.async { self.status = value } }

    func setExposure(iso: Float, duration: Double) {
        queue.async {
            guard let d = self.device, d.isExposureModeSupported(.custom) else { return }
            do {
                try d.lockForConfiguration()
                let time = CMTime(seconds: duration, preferredTimescale: 1_000_000_000)
                let safeISO = min(max(iso, d.activeFormat.minISO), d.activeFormat.maxISO)
                d.setExposureModeCustom(duration: time, iso: safeISO)
                d.unlockForConfiguration()
            } catch { self.setStatus("Błąd ustawiania ekspozycji") }
        }
    }

    func lockFocus() {
        queue.async {
            guard let d = self.device else { return }
            do {
                try d.lockForConfiguration()
                if d.isFocusModeSupported(.locked) { d.focusMode = .locked }
                d.unlockForConfiguration()
                self.setStatus("Ostrość zablokowana")
            } catch { self.setStatus("Nie można zablokować ostrości") }
        }
    }

    func lockWhiteBalance() {
        queue.async {
            guard let d = self.device else { return }
            do {
                try d.lockForConfiguration()
                if d.isWhiteBalanceModeSupported(.locked) {
                    let maxGain = d.maxWhiteBalanceGain
                    var gains = d.deviceWhiteBalanceGains
                    gains.redGain = min(max(1, gains.redGain), maxGain)
                    gains.greenGain = min(max(1, gains.greenGain), maxGain)
                    gains.blueGain = min(max(1, gains.blueGain), maxGain)
                    d.setWhiteBalanceModeLocked(with: gains)
                }
                d.unlockForConfiguration()
                self.setStatus("Balans bieli zablokowany")
            } catch { self.setStatus("Nie można zablokować WB") }
        }
    }

    func resetSampleBuffer() {
        lock.lock(); recentSamples.removeAll(keepingCapacity: true); lock.unlock()
        DispatchQueue.main.async { self.hasReading = false }
        setStatus("Bufor wyczyszczony — czekam na stabilny obraz")
    }

    func captureMeasurement(completion: @escaping (Sample) -> Void) {
        // Wait for the camera pipeline to settle after a pattern change.
        queue.asyncAfter(deadline: .now() + 1.0) {
            self.lock.lock()
            let samples = Array(self.recentSamples.suffix(5))
            let fallback = self.latest
            self.lock.unlock()
            guard !samples.isEmpty else { DispatchQueue.main.async { completion(fallback) }; return }
            func median(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                return sorted[sorted.count / 2]
            }
            let meanLuma = samples.map(\.luma).reduce(0,+) / Double(samples.count)
            let variance = samples.map { pow($0.luma - meanLuma, 2) }.reduce(0,+) / Double(samples.count)
            let cv = meanLuma > 0.0001 ? sqrt(variance) / meanLuma : 0
            let result = Sample(
                r: median(samples.map(\.r)), g: median(samples.map(\.g)), b: median(samples.map(\.b)),
                luma: median(samples.map(\.luma)), spread: median(samples.map(\.spread)),
                clipping: median(samples.map(\.clipping)), pixelCount: median(samples.map(\.pixelCount)),
                temporalVariation: cv, sampleCount: Double(samples.count)
            )
            DispatchQueue.main.async { completion(result) }
        }
    }

    func accept(_ sample: Sample) {
        lock.lock()
        latest = sample
        recentSamples.append(sample)
        if recentSamples.count > 12 { recentSamples.removeFirst(recentSamples.count - 12) }
        lock.unlock()
        frameCounter += 1
        if frameCounter % 8 == 0 {
            DispatchQueue.main.async {
                self.live = sample
                self.hasReading = true
            }
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let x0 = width / 3, x1 = width * 2 / 3, y0 = height / 3, y1 = height * 2 / 3
        var rs = [Double](), gs = [Double](), bs = [Double](), luminances = [Double]()
        var clippedPixels = 0
        func linearize(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        for y in Swift.stride(from: y0, to: y1, by: 6) {
            for x in Swift.stride(from: x0, to: x1, by: 6) {
                let i = y * rowBytes + x * 4
                let b = Double(bytes[i]) / 255
                let g = Double(bytes[i+1]) / 255
                let r = Double(bytes[i+2]) / 255
                rs.append(r); gs.append(g); bs.append(b)
                if r <= 2/255 || g <= 2/255 || b <= 2/255 || r >= 253/255 || g >= 253/255 || b >= 253/255 {
                    clippedPixels += 1
                }
                luminances.append(0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b))
            }
        }
        guard !rs.isEmpty else { return }
        let count = Double(rs.count)
        let r = rs.reduce(0,+) / count
        let g = gs.reduce(0,+) / count
        let b = bs.reduce(0,+) / count
        let luma = luminances.reduce(0,+) / count
        let variance = luminances.reduce(0.0) { $0 + pow($1 - luma, 2) } / count
        let spread = sqrt(variance)
        let clipping = Double(clippedPixels) / count
        accept(Sample(r: r, g: g, b: b, luma: luma, spread: spread, clipping: clipping, pixelCount: count))
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session { uiView.previewLayer.session = session }
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
