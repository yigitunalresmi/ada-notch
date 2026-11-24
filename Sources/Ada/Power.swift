import SwiftUI
import IOKit

// MARK: - Anlık güç verileri (Ayarlar › Güç)

/// Pilin ve adaptörün o anki elektriksel durumu. Değerler macOS'in pil sürücüsünden okunur;
/// bir Mac'te bulunmayan alanlar nil kalır ve sayfada gösterilmez.
struct PowerSnapshot: Equatable {
    var hasBattery = false
    var percent: Int?
    var plugged = false
    var charging = false
    var full = false

    /// Pile giren (+) ya da pilden çıkan (−) güç, watt.
    var batteryWatts: Double?
    /// Adaptörden Mac'e giren güç, watt.
    var inputWatts: Double?
    /// Mac'in o an tükettiği güç, watt.
    var systemWatts: Double?
    var volts: Double?
    var amps: Double?

    var adapterName: String?
    var adapterWatts: Int?
    var adapterVolts: Double?
    var adapterAmps: Double?

    var minutesToFull: Int?
    var minutesToEmpty: Int?

    var cycles: Int?
    var designCycles: Int?
    var healthPercent: Int?
    var currentMAh: Int?
    var fullMAh: Int?
    var designMAh: Int?
    var temperature: Double?
}

final class PowerService: ObservableObject {
    static let shared = PowerService()

    @Published var snap = PowerSnapshot()
    /// Son birkaç dakikanın pil gücü (mutlak değer, watt) — küçük grafik için.
    @Published var history: [Double] = []

    private var timer: Timer?
    private var watchers = 0

    /// Yalnızca sayfa açıkken ölçüm yapılır; kapalıyken hiçbir şey çalışmaz.
    func start() {
        watchers += 1
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
        history = []
    }

    func refresh() {
        let s = PowerService.read()
        if s != snap { snap = s }
        if let w = s.batteryWatts {
            history.append(abs(w))
            if history.count > 90 { history.removeFirst(history.count - 90) }
        }
    }

    /// Sürücü işaretli sayıları bazen işaretsiz 64 bit olarak verir; ikisini de doğru okur.
    private static func int(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber else { return nil }
        return Int(truncatingIfNeeded: n.int64Value)
    }

    static func read() -> PowerSnapshot {
        var s = PowerSnapshot()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return s }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = unmanaged?.takeRetainedValue() as? [String: Any] else { return s }

        s.hasBattery = (d["BatteryInstalled"] as? Bool) ?? true
        s.plugged = (d["ExternalConnected"] as? Bool) ?? false
        s.charging = (d["IsCharging"] as? Bool) ?? false
        s.full = (d["FullyCharged"] as? Bool) ?? false
        s.percent = int(d["CurrentCapacity"])

        let mV = int(d["Voltage"]), mA = int(d["Amperage"]) ?? int(d["InstantAmperage"])
        if let mV { s.volts = Double(mV) / 1000 }
        if let mA { s.amps = Double(mA) / 1000 }
        if let mV, let mA { s.batteryWatts = Double(mV) * Double(mA) / 1_000_000 }

        if let t = d["PowerTelemetryData"] as? [String: Any] {
            if s.plugged, let w = int(t["SystemPowerIn"]), w > 0 { s.inputWatts = Double(w) / 1000 }
            if let w = int(t["SystemLoad"]), w > 0 { s.systemWatts = Double(w) / 1000 }
        }
        // Telemetri yoksa: Mac'in tüketimi = giren güç − pile giden güç (pildeyken pilden çıkan güç).
        if s.systemWatts == nil, let b = s.batteryWatts {
            if let i = s.inputWatts { s.systemWatts = max(0, i - b) } else if !s.plugged { s.systemWatts = max(0, -b) }
        }

        if s.plugged, let a = d["AdapterDetails"] as? [String: Any] {
            s.adapterName = (a["Name"] as? String) ?? (a["Description"] as? String)
            if let w = int(a["Watts"]), w > 0 { s.adapterWatts = w }
            if let v = int(a["AdapterVoltage"]), v > 0 { s.adapterVolts = Double(v) / 1000 }
            if let c = int(a["Current"]), c > 0 { s.adapterAmps = Double(c) / 1000 }
        }

        if let m = int(d["AvgTimeToFull"]), m > 0, m < 65535, s.charging { s.minutesToFull = m }
        if let m = int(d["AvgTimeToEmpty"]), m > 0, m < 65535, !s.plugged { s.minutesToEmpty = m }

        s.cycles = int(d["CycleCount"])
        if let c = int(d["DesignCycleCount9C"]), c > 0 { s.designCycles = c }
        let b = (d["BatteryData"] as? [String: Any]) ?? [:]
        let design = int(d["DesignCapacity"]) ?? int(b["DesignCapacity"])
        let rawMax = int(d["AppleRawMaxCapacity"]) ?? int(b["AppleRawMaxCapacity"]) ?? int(b["FullChargeCapacity"])
        let rawNow = int(d["AppleRawCurrentCapacity"]) ?? int(b["AppleRawCurrentCapacity"]) ?? int(b["RemainingCapacity"])
        if let design, design > 0 { s.designMAh = design }
        if let rawMax, rawMax > 0 { s.fullMAh = rawMax }
        if let rawNow, rawNow > 0 { s.currentMAh = rawNow }
        if let design, let rawMax, design > 0, rawMax > 0 {
            s.healthPercent = min(100, Int((Double(rawMax) / Double(design) * 100).rounded()))
        }
        if let t = int(d["Temperature"]) ?? int(d["VirtualTemperature"]), t > 0 {
            // Sürücü sıcaklığı santigrat derecenin yüzde biri olarak verir.
            let c = Double(t) / 100
            if c > 0, c < 90 { s.temperature = c }
        }
        return s
    }
}

// MARK: - Ayarlar sayfası

struct PowerSettings: View {
    @ObservedObject var power = PowerService.shared

    private func watts(_ w: Double) -> String { String(format: "%.1f W", w) }
    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? Lf("%@ sa %@ dk", "\(minutes / 60)", "\(minutes % 60)") : Lf("%@ dk", "\(minutes)")
    }

    private var headline: (value: String, caption: String, icon: String, tint: Color) {
        let s = power.snap
        guard let w = s.batteryWatts else {
            return ("—", L("Güç verisi okunamadı"), "bolt.slash.fill", .secondary)
        }
        if s.charging || w > 0.5 {
            return (watts(abs(w)), L("ile şarj oluyor"), "bolt.fill", .green)
        }
        if s.plugged {
            return (watts(abs(w)), s.full ? L("Pil dolu, adaptörden çalışıyor") : L("Adaptöre bağlı, şarj olmuyor"), "powerplug.fill", .blue)
        }
        return (watts(abs(w)), L("pilden harcanıyor"), "battery.50", .orange)
    }

    var body: some View {
        let s = power.snap
        Form {
            if !s.hasBattery {
                Section {
                    Label(L("Bu Mac'te pil bulunmuyor; güç verileri yalnızca pilli Mac'lerde gösterilir."), systemImage: "bolt.slash")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: headline.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(headline.tint.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(headline.value)
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text(headline.caption).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        if power.history.count > 2 {
                            Sparkline(values: power.history)
                                .frame(width: 150, height: 40)
                                .opacity(0.9)
                        }
                    }
                    .padding(.vertical, 6)
                    .animation(.easeInOut(duration: 0.3), value: headline.value)
                }

                Section {
                    if let p = s.percent { row(L("Pil düzeyi"), "%\(p)") }
                    if let m = s.minutesToFull { row(L("Dolmasına kalan"), duration(m)) }
                    if let m = s.minutesToEmpty { row(L("Bitmesine kalan"), duration(m)) }
                    if let w = s.inputWatts { row(L("Adaptörden gelen güç"), watts(w)) }
                    if let w = s.systemWatts { row(L("Mac'in harcadığı güç"), watts(w)) }
                    if let v = s.volts { row(L("Pil gerilimi"), String(format: "%.2f V", v)) }
                    if let a = s.amps { row(L("Pil akımı"), String(format: "%+.2f A", a)) }
                } header: {
                    Text(L("Şu an"))
                } footer: {
                    Text(L("Değerler iki saniyede bir yenilenir. Artı akım pilin dolduğunu, eksi akım boşaldığını gösterir."))
                }

                if s.plugged {
                    Section(L("Adaptör")) {
                        if let n = s.adapterName { row(L("Model"), n) }
                        if let w = s.adapterWatts { row(L("Adaptörün gücü"), "\(w) W") }
                        if let v = s.adapterVolts, let a = s.adapterAmps {
                            row(L("Anlaşılan besleme"), String(format: "%.0f V · %.2f A", v, a))
                        }
                        if s.adapterName == nil, s.adapterWatts == nil {
                            Text(L("Adaptör bilgisi alınamadı.")).foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L("Pil sağlığı")) {
                    if let h = s.healthPercent { row(L("Kapasite"), "%\(h)") }
                    if let c = s.cycles {
                        row(L("Şarj döngüsü"), s.designCycles.map { "\(c) / \($0)" } ?? "\(c)")
                    }
                    if let now = s.currentMAh, let full = s.fullMAh {
                        row(L("Şu anki dolum"), "\(now) / \(full) mAh")
                    }
                    if let d = s.designMAh { row(L("Fabrika kapasitesi"), "\(d) mAh") }
                    if let t = s.temperature { row(L("Pil sıcaklığı"), String(format: "%.1f °C", t)) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { power.start() }
        .onDisappear { power.stop() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }
}
