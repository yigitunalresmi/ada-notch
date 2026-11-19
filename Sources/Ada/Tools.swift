import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dosya rafı

final class ShelfService: ObservableObject {
    static let shared = ShelfService()
    @Published var items: [URL] = [] { didSet { UserDefaults.standard.set(items.map(\.path), forKey: "shelf") } }

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: "shelf") ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    if !self.items.contains(url) { self.items.append(url) }
                }
            }
        }
    }

    func remove(_ url: URL) { items.removeAll { $0 == url } }
    func clear() { items = [] }

    func airDrop() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NotchController.shared.close()
        service.perform(withItems: items)
    }
}

struct ShelfView: View {
    @ObservedObject var shelf = ShelfService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: Lf("Raf · %@ dosya", "\(shelf.items.count)"))
                Spacer()
                if !shelf.items.isEmpty {
                    Button { shelf.airDrop() } label: { Label("AirDrop", systemImage: "dot.radiowaves.left.and.right") }
                        .buttonStyle(PillButtonStyle(tint: .blue.opacity(0.7)))
                    Button(L("Temizle")) { shelf.clear() }.buttonStyle(PillButtonStyle())
                }
            }
            if shelf.items.isEmpty {
                EmptyHint(icon: "tray.and.arrow.down", text: L("Dosyaları çentiğe sürükleyip bırakın.\nSonra buradan istediğiniz yere taşıyabilirsiniz."))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shelf.items, id: \.self) { url in
                            VStack(spacing: 5) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 62, height: 62)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 10.5)).lineLimit(2).multilineTextAlignment(.center)
                                    .frame(width: 92)
                            }
                            .padding(8)
                            .glassCard(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onDrag { NSItemProvider(object: url as NSURL) }
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                            .contextMenu {
                                Button(L("Aç")) { NSWorkspace.shared.open(url) }
                                Button(L("Finder'da Göster")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                Button(L("Raftan Kaldır")) { shelf.remove(url) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Pano geçmişi

final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    @Published var items: [String] = []
    private var timer: Timer?
    private var lastCount = NSPasteboard.general.changeCount

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            lastCount = NSPasteboard.general.changeCount
            let t = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !on {
            timer?.invalidate(); timer = nil
            items = []
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        // Parola yöneticilerinin "gizli" olarak işaretlediği içerikleri kaydetme.
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }
        guard let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        let limit = max(5, Int(Prefs.shared.clipboardLimit))
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

// MARK: - Zamanlayıcı

final class CountdownService: ObservableObject {
    static let shared = CountdownService()
    @Published var running = false
    @Published var remaining: Double = 0
    @Published var total: Double = 0
    @Published var label = ""
    @Published var pomodoro = false
    @Published var working = true
    private var end = Date()
    private var timer: Timer?

    /// Ayarlardaki hazır süreler (dakika); geçersizse varsayılanlar.
    static var presets: [Int] {
        let list = Opt.list("timer.presets").compactMap { Int($0) }.filter { $0 > 0 && $0 <= 600 }
        return list.isEmpty ? [5, 15, 25, 45] : Array(list.prefix(6))
    }

    /// Odak ve mola sürelerini sırayla, durdurulana kadar tekrarlar.
    func startPomodoro() {
        begin(minutes: Prefs.shared.pomodoroWork, label: L("Odak"))
        pomodoro = true
        working = true
    }

    func start(minutes: Double, label: String = "") {
        pomodoro = false
        begin(minutes: minutes, label: label)
    }

    private func begin(minutes: Double, label: String) {
        total = minutes * 60
        remaining = total
        end = Date().addingTimeInterval(total)
        self.label = label
        running = true
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
        running = false
        remaining = 0
        pomodoro = false
    }

    private func tick() {
        remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            if Prefs.shared.timerSound { NSSound(named: "Glass")?.play() }
            if pomodoro {
                working.toggle()
                if !working { if Opt.flag("timer.confetti") { NotchModel.shared.celebration += 1 } }
                NotchModel.shared.showHUD(HUDInfo(icon: working ? "brain.head.profile" : "cup.and.saucer.fill",
                                                  title: working ? L("Odak zamanı") : L("Mola zamanı"), tint: .orange), seconds: 5)
                begin(minutes: working ? Prefs.shared.pomodoroWork : Prefs.shared.pomodoroBreak, label: working ? L("Odak") : L("Mola"))
                return
            }
            let name = label.isEmpty ? L("Süre doldu") : Lf("%@ · süre doldu", "\(label)")
            stop()
            if Opt.flag("timer.confetti") { NotchModel.shared.celebration += 1 }
            NotchModel.shared.showHUD(HUDInfo(icon: "bell.fill", title: name, tint: .orange), seconds: 5)
        }
    }
}

// MARK: - Not

final class NotesService: ObservableObject {
    static let shared = NotesService()
    @Published var text: String { didSet { UserDefaults.standard.set(text, forKey: "note") } }
    private init() { text = UserDefaults.standard.string(forKey: "note") ?? "" }
}

// MARK: - Araçlar sekmesi

struct ToolsView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var countdown = CountdownService.shared
    @ObservedObject var clipboard = ClipboardService.shared
    @ObservedObject var notes = NotesService.shared
    @ObservedObject var stats = StatsService.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                if prefs.isOn(.timer) { timerColumn.frame(width: 150) }
                if prefs.isOn(.clipboard) { clipboardColumn.frame(maxWidth: .infinity) }
                if prefs.isOn(.notes) { notesColumn.frame(maxWidth: .infinity) }
            }
            .frame(maxHeight: .infinity)
            QuickActionsRow()
            if prefs.isOn(.stats) { statsRow }
        }
    }

    private var timerColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: L("Zamanlayıcı"))
            if countdown.running {
                Text(formatClock(countdown.remaining))
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                if !countdown.label.isEmpty {
                    Text(countdown.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                ProgressView(value: countdown.total > 0 ? 1 - countdown.remaining / countdown.total : 0)
                    .tint(.orange)
                Button(L("Durdur")) { countdown.stop() }.buttonStyle(PillButtonStyle(tint: .red.opacity(0.6)))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(CountdownService.presets, id: \.self) { m in
                        Button(Lf("%@ dk", "\(m)")) { countdown.start(minutes: Double(m)) }
                            .buttonStyle(PillButtonStyle())
                            .frame(maxWidth: .infinity)
                    }
                }
                Button { countdown.startPomodoro() } label: { Label("Pomodoro", systemImage: "brain.head.profile") }
                    .buttonStyle(PillButtonStyle(tint: .orange.opacity(0.55)))
            }
            Spacer(minLength: 0)
        }
    }

    private var clipboardColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L("Pano"))
            if clipboard.items.isEmpty {
                Text(L("Kopyaladıklarınız burada görünür.")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(clipboard.items, id: \.self) { item in
                            Button { clipboard.copy(item) } label: {
                                Text(item)
                                    .font(.system(size: 11)).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .glassCard(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(L("Yeniden kopyala"))
                        }
                    }
                }
            }
        }
    }

    private var notesColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: L("Not"))
            TextEditor(text: $notes.text)
                .font(.system(size: Opt.num("notes.font")))
                .scrollContentBackground(.hidden)
                .padding(6)
                .glassCard(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            stat("cpu", L("İşlemci"), "%\(Int((stats.cpu * 100).rounded()))")
            if Opt.flag("stats.graph") {
                Sparkline(values: stats.cpuHistory).frame(width: 46, height: 12).padding(.leading, -8)
            }
            stat("memorychip", L("Bellek"), String(format: "%.1f / %.0f GB", stats.memUsed / 1_073_741_824, stats.memTotal / 1_073_741_824))
            stat("arrow.down", L("İndirme"), StatsService.rate(stats.netDown))
            stat("arrow.up", L("Yükleme"), StatsService.rate(stats.netUp))
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5).monospacedDigit())
    }

    private func stat(_ icon: String, _ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(.white.opacity(0.45))
            Text(name).foregroundStyle(.white.opacity(0.45))
            Text(value).fontWeight(.semibold)
        }
    }
}

// MARK: - Ayna

final class CameraService: ObservableObject {
    static let shared = CameraService()
    let session = AVCaptureSession()
    @Published var denied = false
    private var configured = false
    private let queue = DispatchQueue(label: "ada.camera")

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else {
                DispatchQueue.main.async { self.denied = true }
                return
            }
            self.queue.async {
                if !self.configured {
                    guard let dev = AVCaptureDevice.default(for: .video),
                          let input = try? AVCaptureDeviceInput(device: dev),
                          self.session.canAddInput(input) else { return }
                    self.session.addInput(input)
                    self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }
}

final class CameraPreviewNSView: NSView {
    private let preview = AVCaptureVideoPreviewLayer(session: CameraService.shared.session)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.setAffineTransform(.identity)
        preview.frame = bounds
        preview.setAffineTransform(CGAffineTransform(scaleX: Opt.flag("mirror.flip") ? -1 : 1, y: 1)) // ayna görüntüsü
        CATransaction.commit()
    }
}

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewNSView { CameraPreviewNSView(frame: .zero) }
    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {}
}

struct MirrorView: View {
    @ObservedObject var camera = CameraService.shared

    var body: some View {
        Group {
            if camera.denied {
                EmptyHint(icon: "video.slash", text: L("Kamera izni verilmedi.\nSistem Ayarları › Gizlilik ve Güvenlik › Kamera'dan açabilirsiniz."))
            } else {
                CameraPreview()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(width: Opt.num("mirror.width"))
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}
