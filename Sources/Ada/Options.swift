import AppKit
import SwiftUI

// MARK: - Modül başına ince ayarlar
//
// Her modül kendi ayarlarını burada bildirir. Değerler Prefs.options içinde saklanır;
// kod `Opt.num("music.poll")` gibi çağrılarla okur, kayıtlı değer yoksa buradaki varsayılan kullanılır.

struct ModuleOption: Identifiable {
    enum Kind {
        case toggle
        /// `format`, değeri gösteren bir String(format:) kalıbıdır (ör. "%.1f sn").
        case slider(ClosedRange<Double>, step: Double, format: String)
        case text(placeholder: String)
        case choice([(value: String, label: String)])
    }

    let key: String
    let title: String
    let kind: Kind
    let fallback: Any
    var id: String { key }
}

enum Opt {
    private static func t(_ key: String, _ title: String, _ on: Bool) -> ModuleOption {
        ModuleOption(key: key, title: title, kind: .toggle, fallback: on)
    }

    private static func s(_ key: String, _ title: String, _ range: ClosedRange<Double>, _ step: Double, _ format: String, _ value: Double) -> ModuleOption {
        ModuleOption(key: key, title: title, kind: .slider(range, step: step, format: format), fallback: value)
    }

    private static func x(_ key: String, _ title: String, _ placeholder: String, _ value: String) -> ModuleOption {
        ModuleOption(key: key, title: title, kind: .text(placeholder: placeholder), fallback: value)
    }

    static let all: [ModuleID: [ModuleOption]] = [
        .music: [
            s("music.poll", L("Yenileme aralığı"), 0.5...3, 0.5, L("%.1f sn"), 1.0),
            ModuleOption(key: "music.prefer", title: L("Öncelikli oynatıcı"),
                         kind: .choice([("auto", L("Çalan hangisiyse")), ("spotify", "Spotify"), ("music", "Apple Music")]), fallback: "auto"),
            s("music.artSize", L("Kapak boyutu"), 70...140, 2, "%.0f pt", 112),
            t("music.shrink", L("Duraklatınca kapağı küçült"), true),
            t("music.trackHUD", L("Parça değişince çentikte göster"), false),
        ],
        .lyrics: [
            s("lyrics.offset", L("Zamanlama kayması"), -2...2, 0.1, L("%+.1f sn"), 0),
            t("lyrics.accent", L("Vurgu rengini kullan"), false),
        ],
        .calendar: [
            s("calendar.days", L("Kaç gün ileriye bakılsın"), 1...7, 1, L("%.0f gün"), 3),
            s("calendar.count", L("En fazla etkinlik"), 1...5, 1, "%.0f", 2),
            t("calendar.allDay", L("Tüm gün süren etkinlikleri göster"), true),
            s("calendar.lead", L("Geri sayım kaç dakika önce başlasın"), 10...120, 5, L("%.0f dk"), 60),
        ],
        .reminders: [
            s("reminders.count", L("En fazla anımsatıcı"), 1...5, 1, "%.0f", 1),
            t("reminders.onlyDue", L("Yalnızca tarihi olanları göster"), false),
        ],
        .weather: [
            s("weather.refresh", L("Yenileme aralığı"), 10...120, 10, L("%.0f dk"), 20),
            s("weather.hours", L("Tahminde saat sayısı"), 4...8, 1, "%.0f", 6),
            t("weather.rain", L("Yağış olasılığını göster"), true),
        ],
        .ticker: [
            s("ticker.refresh", L("Yenileme aralığı"), 10...300, 10, L("%.0f sn"), 30),
            s("ticker.count", L("Gösterilecek sembol sayısı"), 1...4, 1, "%.0f", 3),
        ],
        .clocks: [
            x("clocks.zones", L("Saat dilimleri"), "Europe/London, America/New_York", "Europe/London, America/New_York"),
            t("clocks.h24", L("24 saat biçimi"), true),
        ],
        .battery: [
            s("battery.low", L("Düşük pil uyarı eşiği"), 5...30, 5, "%%%.0f", 20),
            t("battery.plugHUD", L("Şarja takınca ve çıkarınca bildir"), true),
            s("battery.notifyAt", L("Şarj bu düzeye gelince haber ver (0 = kapalı)"), 0...100, 5, "%%%.0f", 0),
        ],
        .bluetooth: [
            t("bluetooth.disconnect", L("Cihaz ayrılınca da bildir"), true),
            t("bluetooth.battery", L("Bağlanınca pil düzeyini göster"), true),
        ],
        .hud: [
            s("hud.steps", L("Kademe sayısı"), 8...64, 8, "%.0f", 16),
            s("hud.duration", L("Gösterim süresi"), 0.8...3, 0.2, L("%.1f sn"), 1.6),
            t("hud.caps", L("Caps Lock göstergesi"), true),
        ],
        .xdr: [
            s("xdr.step", L("Her basışta artış"), 0.05...0.2, 0.05, "%.2f×", 0.1),
        ],
        .privacy: [
            t("privacy.hud", L("Kullanım başlayınca bildirim göster"), true),
            t("privacy.micHotkey", L("⌥M ile mikrofonu kapat/aç"), true),
        ],
        .clipboard: [
            t("clipboard.images", L("Görselleri de sakla"), true),
            t("clipboard.clickPastes", L("Tıklayınca doğrudan yapıştır"), false),
            t("clipboard.hotkey", L("⌥⇧V ile panoyu aç"), true),
            t("clipboard.persist", L("Metinleri yeniden başlatınca da sakla"), false),
        ],
        .network: [t("network.switch", L("Ağ değişince de bildir"), true)],
        .downloads: [t("downloads.done", L("İndirme bitince bildir"), true)],
        .timer: [
            x("timer.presets", L("Hazır süreler (dakika)"), "5, 15, 25, 45", "5, 15, 25, 45"),
            t("timer.confetti", L("Süre bitince konfeti"), true),
        ],
        .breaks: [
            s("breaks.interval", L("Hatırlatma aralığı"), 15...120, 5, L("%.0f dk"), 50),
            x("breaks.message", L("Mesaj (boşsa varsayılan)"), L("Mola zamanı — kalkıp biraz esneyin"), ""),
            t("breaks.sound", L("Ses çal"), false),
        ],
        .notes: [s("notes.font", L("Yazı boyutu"), 10...16, 1, "%.0f pt", 12)],
        .stats: [
            s("stats.interval", L("Ölçüm aralığı"), 1...5, 1, L("%.0f sn"), 2),
            t("stats.graph", L("İşlemci grafiğini göster"), true),
        ],
        .shelf: [t("shelf.autoOpen", L("Dosya sürüklenince raf sekmesine geç"), true)],
        .launcher: [
            s("launcher.icon", L("Simge boyutu"), 36...64, 2, "%.0f pt", 52),
            t("launcher.close", L("Uygulama açınca çentiği kapat"), true),
        ],
        .mirror: [
            t("mirror.flip", L("Ayna görüntüsü (yatay çevir)"), true),
            s("mirror.width", L("Genişlik"), 240...520, 20, "%.0f pt", 400),
        ],
        .notifications: [
            s("notifications.duration", L("Gösterim süresi"), 2...8, 0.5, L("%.1f sn"), 4.5),
            t("notifications.hideBody", L("İçeriği gizle, yalnızca göndereni göster"), false),
            x("notifications.ignore", L("Yok sayılacak uygulamalar (virgülle)"), "Mail, Slack", ""),
        ],
        .visualizer: [s("visualizer.gain", L("Hassasiyet"), 0.5...2.5, 0.1, "%.1f×", 1.0)],
        .screenshots: [t("screenshots.hud", L("Rafa eklenince bildir"), true)],
    ]

    static let fallbacks: [String: Any] = {
        var d: [String: Any] = [:]
        for list in all.values { for o in list { d[o.key] = o.fallback } }
        return d
    }()

    private static func value(_ key: String) -> Any? { Prefs.shared.options[key] ?? fallbacks[key] }

    static func num(_ key: String) -> Double {
        let v = value(key)
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        return 0
    }

    static func flag(_ key: String) -> Bool {
        let v = value(key)
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return false
    }

    static func str(_ key: String) -> String { value(key) as? String ?? "" }

    /// Virgülle ayrılmış bir metin ayarını temizlenmiş parçalara böler.
    static func list(_ key: String) -> [String] {
        str(key).components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// MARK: - Ayar penceresi

struct ModuleOptionsView: View {
    let module: ModuleID
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let options = Opt.all[module] ?? []
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: module.icon).foregroundStyle(.secondary)
                Text(module.title).font(.headline)
                Spacer()
                Button(L("Varsayılana dön")) {
                    for o in options { prefs.options.removeValue(forKey: o.key) }
                }
                .controlSize(.small)
            }
            Divider()
            ForEach(options) { option in
                row(option)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    @ViewBuilder private func row(_ o: ModuleOption) -> some View {
        switch o.kind {
        case .toggle:
            Toggle(o.title, isOn: Binding(get: { Opt.flag(o.key) }, set: { prefs.options[o.key] = $0 }))
        case let .slider(range, step, format):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(o.title)
                    Spacer()
                    Text(String(format: format, Opt.num(o.key))).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { Opt.num(o.key) }, set: { prefs.options[o.key] = (($0 / step).rounded() * step) }), in: range)
            }
        case let .text(placeholder):
            VStack(alignment: .leading, spacing: 3) {
                Text(o.title)
                TextField(placeholder, text: Binding(get: { Opt.str(o.key) }, set: { prefs.options[o.key] = $0 }))
                    .textFieldStyle(.roundedBorder)
            }
        case let .choice(items):
            Picker(o.title, selection: Binding(get: { Opt.str(o.key) }, set: { prefs.options[o.key] = $0 })) {
                ForEach(items, id: \.value) { Text($0.label).tag($0.value) }
            }
        }
    }
}

// MARK: - Dünya saatleri

struct ClocksRow: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let zones = Opt.list("clocks.zones").compactMap { TimeZone(identifier: $0) }.prefix(4)
        if zones.isEmpty {
            Text(L("Saat dilimi ekleyin (ör. Europe/London)")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
        } else {
            TimelineView(.periodic(from: .now, by: 20)) { ctx in
                HStack(spacing: 12) {
                    ForEach(Array(zones), id: \.identifier) { zone in
                        HStack(spacing: 4) {
                            Text(Self.city(zone)).foregroundStyle(.white.opacity(0.55))
                            Text(Self.time(ctx.date, zone)).fontWeight(.semibold)
                        }
                    }
                }
                .font(.system(size: 10.5).monospacedDigit())
                .lineLimit(1)
            }
        }
    }

    /// "America/New_York" → "New York"
    private static func city(_ zone: TimeZone) -> String {
        (zone.identifier.components(separatedBy: "/").last ?? zone.identifier).replacingOccurrences(of: "_", with: " ")
    }

    private static func time(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.locale = appLocale
        f.dateFormat = Opt.flag("clocks.h24") ? "HH:mm" : "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Mola hatırlatıcı

final class BreakReminder {
    static let shared = BreakReminder()
    private var timer: Timer?
    private var workedSeconds: Double = 0

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            workedSeconds = 0
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !on {
            timer?.invalidate(); timer = nil
        }
    }

    private func tick() {
        // Bilgisayar başında değilseniz (5 dakikadır tuşa/fareye dokunulmadıysa) sayaç sıfırlanır: zaten mola verdiniz.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle > 300 {
            workedSeconds = 0
            return
        }
        workedSeconds += 30
        guard workedSeconds >= Opt.num("breaks.interval") * 60 else { return }
        workedSeconds = 0
        let custom = Opt.str("breaks.message").trimmingCharacters(in: .whitespaces)
        NotchModel.shared.showHUD(HUDInfo(icon: "figure.walk", title: custom.isEmpty ? L("Mola zamanı — kalkıp biraz esneyin") : custom,
                                          leftText: L("Mola"), wide: true, tint: .mint), seconds: 6)
        if Opt.flag("breaks.sound") { NSSound(named: "Purr")?.play() }
    }
}
