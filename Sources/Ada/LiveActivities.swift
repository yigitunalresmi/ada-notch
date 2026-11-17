import AppKit
import CoreAudio
import CoreMediaIO
import Network
import SwiftUI

// MARK: - Gizlilik göstergeleri (kamera / mikrofon kullanımda mı)

final class PrivacyService: ObservableObject {
    static let shared = PrivacyService()

    @Published var cameraOn = false
    @Published var micOn = false
    private var timer: Timer?

    var anyOn: Bool { cameraOn || micOn }

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            poll()
        } else if !on {
            timer?.invalidate(); timer = nil
            cameraOn = false
            micOn = false
        }
    }

    private func poll() {
        let cam = Self.cameraInUse()
        let mic = Self.micInUse()
        if cam, !cameraOn {
            NotchModel.shared.showHUD(HUDInfo(icon: "video.fill", title: L("Kamera kullanılıyor"), tint: .green), seconds: 2.4)
        }
        if mic, !micOn, !cam {
            NotchModel.shared.showHUD(HUDInfo(icon: "mic.fill", title: L("Mikrofon kullanılıyor"), tint: .orange), seconds: 2.4)
        }
        if cam != cameraOn { cameraOn = cam }
        if mic != micOn { micOn = mic }
    }

    private static func micInUse() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return false }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return false }
        for id in ids {
            // Yalnızca giriş (mikrofon) akışı olan aygıtlar
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var ssize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &ssize) == noErr, ssize > 0 else { continue }
            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var vsize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &running, 0, nil, &vsize, &value) == noErr, value != 0 { return true }
        }
        return false
    }

    private static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(sys, &addr, 0, nil, size, &used, &ids) == noErr else { return false }
        for id in ids {
            var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var value: UInt32 = 0
            var vused: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &vused, &value) == noErr, value != 0 {
                return true
            }
        }
        return false
    }
}

struct PrivacyDots: View {
    @ObservedObject var privacy = PrivacyService.shared
    var body: some View {
        HStack(spacing: 4) {
            if privacy.cameraOn { Circle().fill(.green).frame(width: 7, height: 7) }
            if privacy.micOn { Circle().fill(.orange).frame(width: 7, height: 7) }
        }
    }
}

// MARK: - İndirme takibi

final class DownloadsService: ObservableObject {
    static let shared = DownloadsService()

    struct Item: Equatable {
        var name: String
        var bytes: Int64
    }

    /// Süren indirmelerden ilki.
    @Published var current: Item?
    @Published var count = 0

    private var timer: Timer?
    private var known: [String: String] = [:] // geçici dosya yolu → görünen ad
    private let queue = DispatchQueue(label: "ada.downloads")
    private static let partial: Set<String> = ["crdownload", "download", "part", "opdownload", "partial"]

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.scan() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            scan()
        } else if !on {
            timer?.invalidate(); timer = nil
            current = nil
            count = 0
            known = [:]
        }
    }

    private func scan() {
        queue.async {
            let fm = FileManager.default
            guard let dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
                  let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey],
                                                         options: [.skipsHiddenFiles]) else { return }
            var active: [String: (name: String, bytes: Int64)] = [:]
            for u in urls where Self.partial.contains(u.pathExtension.lowercased()) {
                let name = u.deletingPathExtension().lastPathComponent
                let v = try? u.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
                let bytes = Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
                active[u.path] = (name, bytes)
            }
            DispatchQueue.main.async { self.apply(active) }
        }
    }

    private func apply(_ active: [String: (name: String, bytes: Int64)]) {
        for (path, name) in known where active[path] == nil {
            // Geçici dosya kayboldu: indirme bitti (ya da iptal edildi).
            let finished = (path as NSString).deletingPathExtension
            if FileManager.default.fileExists(atPath: finished) {
                NotchModel.shared.showHUD(HUDInfo(icon: "checkmark.circle.fill", title: Lf("İndirildi: %@", name), tint: .green), seconds: 3)
            }
        }
        known = active.mapValues { $0.name }
        count = active.count
        let first = active.values.sorted { $0.name < $1.name }.first
        let item = first.map { Item(name: $0.name, bytes: $0.bytes) }
        if item != current { current = item }
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Ağ bildirimleri

final class NetworkService {
    static let shared = NetworkService()
    private var monitor: NWPathMonitor?
    private var last: (online: Bool, kind: String)?

    func setEnabled(_ on: Bool) {
        if on, monitor == nil {
            let m = NWPathMonitor()
            m.pathUpdateHandler = { [weak self] path in
                DispatchQueue.main.async { self?.changed(path) }
            }
            m.start(queue: DispatchQueue(label: "ada.network"))
            monitor = m
        } else if !on {
            monitor?.cancel()
            monitor = nil
            last = nil
        }
    }

    private func changed(_ path: NWPath) {
        let online = path.status == .satisfied
        let kind = path.usesInterfaceType(.wifi) ? "wifi" : (path.usesInterfaceType(.wiredEthernet) ? "ethernet" : (path.usesInterfaceType(.cellular) ? "cellular" : "other"))
        defer { last = (online, kind) }
        guard let last else { return } // ilk durum: bildirim yok
        if online != last.online {
            NotchModel.shared.showHUD(HUDInfo(icon: online ? "wifi" : "wifi.slash",
                                              title: online ? L("İnternet bağlantısı geri geldi") : L("İnternet bağlantısı kesildi"),
                                              tint: online ? .green : .red), seconds: 3)
        } else if online, kind != last.kind {
            let name = kind == "wifi" ? "Wi‑Fi" : (kind == "ethernet" ? "Ethernet" : (kind == "cellular" ? L("Kişisel erişim noktası") : L("Ağ")))
            NotchModel.shared.showHUD(HUDInfo(icon: kind == "ethernet" ? "cable.connector" : "wifi", title: Lf("%@ üzerinden bağlı", name), tint: .blue), seconds: 2.6)
        }
    }
}

// MARK: - Caps Lock göstergesi

final class CapsLockMonitor {
    static let shared = CapsLockMonitor()
    private var monitors: [Any] = []
    private var state = NSEvent.modifierFlags.contains(.capsLock)

    func setEnabled(_ on: Bool) {
        if on, monitors.isEmpty {
            let handler: (NSEvent) -> Void = { [weak self] e in self?.check(e.modifierFlags) }
            if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) { monitors.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in handler(e); return e }) { monitors.append(l) }
        } else if !on {
            monitors.forEach { NSEvent.removeMonitor($0) }
            monitors = []
        }
    }

    private func check(_ flags: NSEvent.ModifierFlags) {
        let caps = flags.contains(.capsLock)
        guard caps != state else { return }
        state = caps
        NotchModel.shared.showHUD(HUDInfo(icon: caps ? "capslock.fill" : "capslock",
                                          title: caps ? L("Caps Lock açık") : L("Caps Lock kapalı"),
                                          tint: caps ? .green : .gray), seconds: 1.4)
    }
}

// MARK: - Piyasa takibi (Binance'in herkese açık fiyat verisi)

struct Quote: Identifiable, Equatable {
    var id: String { symbol }
    var symbol: String
    var price: Double
    var change: Double
}

final class TickerService: ObservableObject {
    static let shared = TickerService()
    @Published var quotes: [Quote] = []
    private var timer: Timer?

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.fetch() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            fetch()
        } else if !on {
            timer?.invalidate(); timer = nil
            quotes = []
        }
    }

    static func symbols() -> [String] {
        Prefs.shared.tickerSymbols.uppercased()
            .components(separatedBy: CharacterSet(charactersIn: ", ;"))
            .filter { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber } }
    }

    func fetch() {
        let symbols = Self.symbols()
        guard !symbols.isEmpty else { quotes = []; return }
        let list = "[" + symbols.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        var comps = URLComponents(string: "https://api.binance.com/api/v3/ticker/24hr")!
        comps.queryItems = [URLQueryItem(name: "symbols", value: list)]
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            var out: [Quote] = []
            for s in symbols {
                guard let d = arr.first(where: { $0["symbol"] as? String == s }),
                      let p = Double(d["lastPrice"] as? String ?? ""), let c = Double(d["priceChangePercent"] as? String ?? "") else { continue }
                out.append(Quote(symbol: s, price: p, change: c))
            }
            DispatchQueue.main.async { self.quotes = out }
        }.resume()
    }

    static func price(_ p: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = appLocale
        f.maximumFractionDigits = p >= 1000 ? 0 : (p >= 1 ? 2 : 5)
        return f.string(from: NSNumber(value: p)) ?? "\(p)"
    }

    /// "BTCUSDT" → "BTC"
    static func short(_ symbol: String) -> String {
        for suffix in ["USDT", "USDC", "BUSD", "TRY", "EUR", "USD"] where symbol.hasSuffix(suffix) && symbol.count > suffix.count {
            return String(symbol.dropLast(suffix.count)) + (suffix == "TRY" ? "/TRY" : (suffix == "EUR" ? "/EUR" : ""))
        }
        return symbol
    }
}

struct TickerRow: View {
    @ObservedObject var ticker = TickerService.shared

    var body: some View {
        if ticker.quotes.isEmpty {
            Text(L("Fiyatlar yükleniyor…")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
        } else {
            HStack(spacing: 12) {
                ForEach(ticker.quotes.prefix(3)) { q in
                    HStack(spacing: 4) {
                        Text(TickerService.short(q.symbol)).foregroundStyle(.white.opacity(0.55))
                        Text(TickerService.price(q.price)).fontWeight(.semibold)
                        Text(String(format: "%@%.1f%%", q.change >= 0 ? "▲" : "▼", abs(q.change)))
                            .foregroundStyle(q.change >= 0 ? Color.green : Color.red)
                    }
                }
            }
            .font(.system(size: 10.5).monospacedDigit())
            .lineLimit(1)
        }
    }
}

// MARK: - Bluetooth cihaz pili

enum BluetoothBattery {
    /// Bağlı cihazın pil düzeylerini okur (ör. "Sol %80 · Sağ %75"). Yavaş olduğundan arka planda çağrılır.
    static func levels(for name: String) -> String? {
        let r = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 10)
        guard r.code == 0, let data = r.out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                guard let info = entry[name] as? [String: Any] else { continue }
                var parts: [String] = []
                func add(_ key: String, _ label: String) {
                    if let v = info[key] as? String { parts.append("\(label) %\(v.replacingOccurrences(of: "%", with: ""))") }
                }
                add("device_batteryLevelLeft", L("Sol"))
                add("device_batteryLevelRight", L("Sağ"))
                add("device_batteryLevelCase", L("Kutu"))
                if parts.isEmpty { add("device_batteryLevelMain", L("Pil")) }
                return parts.isEmpty ? nil : parts.joined(separator: " · ")
            }
        }
        return nil
    }
}
