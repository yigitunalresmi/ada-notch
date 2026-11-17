import AppKit
import Combine
import SwiftUI

// MARK: - Yerelleştirme
//
// Kaynak metinler Türkçedir; `Resources/en.lproj/Localizable.strings` İngilizce karşılıklarını tutar.

/// Arayüz metnini uygulamanın diline çevirir.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Yer tutuculu (%@) metni çevirip değerleri yerleştirir.
func Lf(_ key: String, _ args: String...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}

/// Uygulamanın o an kullandığı dil kodu ("tr" ya da "en").
let appLanguage: String = Bundle.main.preferredLocalizations.first ?? "en"
let appLocale = Locale(identifier: appLanguage == "tr" ? "tr_TR" : "en_US")

enum AppLanguage {
    /// "system", "tr" ya da "en"
    static var selection: String {
        guard let langs = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = langs.first else { return "system" }
        return first.hasPrefix("tr") ? "tr" : "en"
    }

    /// Dili değiştirir ve Ada'yı yeniden başlatır.
    static func set(_ code: String) {
        guard code != selection else { return }
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Modüller

enum ModuleID: String, CaseIterable, Identifiable {
    case music, lyrics, calendar, reminders, weather, battery, bluetooth, hud, xdr, stats
    case shelf, clipboard, timer, notes, mirror, launcher, assistant
    case privacy, downloads, network, ticker

    /// İzin penceresi açtığı ya da dışarıya istek gönderdiği için kapalı gelen modüller.
    static let defaultOff: Set<ModuleID> = [.downloads, .ticker]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return L("Müzik")
        case .lyrics: return L("Şarkı sözleri")
        case .calendar: return L("Takvim")
        case .reminders: return L("Anımsatıcılar")
        case .weather: return L("Hava durumu")
        case .battery: return L("Pil ve şarj")
        case .bluetooth: return L("Bluetooth bildirimleri")
        case .hud: return L("Ses ve parlaklık göstergesi")
        case .xdr: return L("Ekstra parlaklık (HDR)")
        case .stats: return L("Sistem istatistikleri")
        case .shelf: return L("Dosya rafı")
        case .clipboard: return L("Pano geçmişi")
        case .timer: return L("Zamanlayıcı")
        case .notes: return L("Hızlı not")
        case .mirror: return L("Ayna")
        case .launcher: return L("Uygulama başlatıcı")
        case .privacy: return L("Kamera ve mikrofon göstergesi")
        case .downloads: return L("İndirme takibi")
        case .network: return L("Ağ bildirimleri")
        case .ticker: return L("Piyasa takibi")
        case .assistant: return L("Asistan")
        }
    }

    var icon: String {
        switch self {
        case .music: return "music.note"
        case .lyrics: return "quote.bubble"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .weather: return "cloud.sun"
        case .battery: return "battery.75"
        case .bluetooth: return "headphones"
        case .hud: return "speaker.wave.2"
        case .xdr: return "sun.max.trianglebadge.exclamationmark"
        case .stats: return "cpu"
        case .shelf: return "tray.full"
        case .clipboard: return "doc.on.clipboard"
        case .timer: return "timer"
        case .notes: return "note.text"
        case .mirror: return "person.crop.square"
        case .launcher: return "square.grid.3x3"
        case .privacy: return "video.badge.checkmark"
        case .downloads: return "arrow.down.circle"
        case .network: return "wifi"
        case .ticker: return "chart.line.uptrend.xyaxis"
        case .assistant: return "sparkles"
        }
    }

    var detail: String {
        switch self {
        case .music: return L("Spotify ve Apple Music'te çalan parçayı gösterir, kontrol eder.")
        case .lyrics: return L("Çalan parçanın sözlerini lrclib.net'ten getirir (parça ve sanatçı adı gönderilir).")
        case .calendar: return L("Yaklaşan etkinlikleri gösterir.")
        case .reminders: return L("Tamamlanmamış anımsatıcıları gösterir.")
        case .weather: return L("Konumunuza göre hava durumu (Open‑Meteo'ya yaklaşık konum gönderilir).")
        case .battery: return L("Pil yüzdesi ve şarja takma/çıkarma bildirimi.")
        case .bluetooth: return L("Bir cihaz bağlandığında çentikte gösterir.")
        case .hud: return L("Ses ve parlaklık tuşlarında macOS göstergesi yerine çentikte gösterge. Erişilebilirlik izni ister.")
        case .xdr: return L("Parlaklık %100'deyken artırma tuşuna basmaya devam edince XDR ekranın HDR aralığını kullanır. Pili daha hızlı tüketir.")
        case .stats: return L("İşlemci, bellek ve ağ kullanımı.")
        case .shelf: return L("Dosyaları çentiğe sürükleyip bırakın, sonra istediğiniz yere taşıyın ya da AirDrop ile gönderin.")
        case .clipboard: return L("Kopyaladığınız son metinleri saklar (yalnızca bu Mac'te).")
        case .timer: return L("Geri sayım; kalan süre kapalı çentikte görünür.")
        case .notes: return L("Çentikte küçük bir not defteri.")
        case .mirror: return L("Kamerayı ayna olarak kullanır.")
        case .launcher: return L("Sık kullandığınız uygulamaları çentikten açın.")
        case .privacy: return L("Bir uygulama kamerayı ya da mikrofonu kullanırken çentikte nokta gösterir.")
        case .downloads: return L("İndirilenler klasöründeki süren indirmeleri çentikte gösterir. Klasöre erişim izni ister.")
        case .network: return L("İnternet bağlantısı kesildiğinde, geri geldiğinde ya da ağ değiştiğinde bildirir.")
        case .ticker: return L("Seçtiğiniz kripto fiyatlarını Ana sekmede gösterir (Binance'in açık verisinden).")
        case .assistant: return L("Claude ile sohbet; takvim, müzik ve Mac ayarlarını sizin için yönetir.")
        }
    }
}

// MARK: - Tercihler

final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var modules: [String: Bool] { didSet { d.set(modules, forKey: "modules") } }
    @Published var openOnHover: Bool { didSet { d.set(openOnHover, forKey: "openOnHover") } }
    @Published var hoverDelay: Double { didSet { d.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var glass: Bool { didSet { d.set(glass, forKey: "glass") } }
    @Published var hotkey: Bool { didSet { d.set(hotkey, forKey: "hotkey") } }
    @Published var model: String { didSet { d.set(model, forKey: "model") } }
    @Published var speakReplies: Bool { didSet { d.set(speakReplies, forKey: "speakReplies") } }
    @Published var speechLocale: String { didSet { d.set(speechLocale, forKey: "speechLocale") } }
    @Published var allowAppleScript: Bool { didSet { d.set(allowAppleScript, forKey: "allowAppleScript") } }
    @Published var allowScreen: Bool { didSet { d.set(allowScreen, forKey: "allowScreen") } }
    @Published var allowWeb: Bool { didSet { d.set(allowWeb, forKey: "allowWeb") } }
    @Published var glassClarity: Double { didSet { d.set(glassClarity, forKey: "glassClarity") } }
    @Published var expandedWidth: Double { didSet { d.set(expandedWidth, forKey: "expandedWidth") } }
    @Published var expandedHeight: Double { didSet { d.set(expandedHeight, forKey: "expandedHeight") } }
    @Published var cornerRadius: Double { didSet { d.set(cornerRadius, forKey: "cornerRadius") } }
    @Published var accent: String { didSet { d.set(accent, forKey: "accent") } }
    @Published var showMusicWings: Bool { didSet { d.set(showMusicWings, forKey: "showMusicWings") } }
    @Published var closeDelay: Double { didSet { d.set(closeDelay, forKey: "closeDelay") } }
    @Published var rememberTab: Bool { didSet { d.set(rememberTab, forKey: "rememberTab") } }
    @Published var fahrenheit: Bool { didSet { d.set(fahrenheit, forKey: "fahrenheit") } }
    @Published var clipboardLimit: Double { didSet { d.set(clipboardLimit, forKey: "clipboardLimit") } }
    @Published var hdrMax: Double { didSet { d.set(hdrMax, forKey: "hdrMax") } }
    @Published var timerSound: Bool { didSet { d.set(timerSound, forKey: "timerSound") } }
    @Published var effort: String { didSet { d.set(effort, forKey: "effort") } }
    @Published var customInstructions: String { didSet { d.set(customInstructions, forKey: "customInstructions") } }
    @Published var showMeeting: Bool { didSet { d.set(showMeeting, forKey: "showMeeting") } }
    @Published var pomodoroWork: Double { didSet { d.set(pomodoroWork, forKey: "pomodoroWork") } }
    @Published var pomodoroBreak: Double { didSet { d.set(pomodoroBreak, forKey: "pomodoroBreak") } }
    @Published var pinnedApps: [String] { didSet { d.set(pinnedApps, forKey: "pinnedApps") } }
    @Published var theme: String { didSet { d.set(theme, forKey: "theme") } }
    @Published var color1: String { didSet { d.set(color1, forKey: "color1") } }
    @Published var color2: String { didSet { d.set(color2, forKey: "color2") } }
    @Published var warmth: Double { didSet { d.set(warmth, forKey: "warmth"); tuningChanged() } }
    @Published var contrast: Double { didSet { d.set(contrast, forKey: "contrast"); tuningChanged() } }
    @Published var dim: Double { didSet { d.set(dim, forKey: "dim"); tuningChanged() } }
    @Published var tickerSymbols: String { didSet { d.set(tickerSymbols, forKey: "tickerSymbols"); DispatchQueue.main.async { TickerService.shared.fetch() } } }
    @Published var memory: [String] { didSet { d.set(memory, forKey: "memory") } }

    private init() {
        modules = (d.dictionary(forKey: "modules") as? [String: Bool]) ?? [:]
        openOnHover = d.object(forKey: "openOnHover") as? Bool ?? true
        hoverDelay = d.object(forKey: "hoverDelay") as? Double ?? 0.12
        haptics = d.object(forKey: "haptics") as? Bool ?? true
        glass = d.object(forKey: "glass") as? Bool ?? true
        hotkey = d.object(forKey: "hotkey") as? Bool ?? true
        model = d.string(forKey: "model") ?? "claude-opus-5-5"
        speakReplies = d.object(forKey: "speakReplies") as? Bool ?? false
        speechLocale = d.string(forKey: "speechLocale") ?? (appLanguage == "tr" ? "tr-TR" : "en-US")
        allowAppleScript = d.object(forKey: "allowAppleScript") as? Bool ?? false
        allowScreen = d.object(forKey: "allowScreen") as? Bool ?? false
        allowWeb = d.object(forKey: "allowWeb") as? Bool ?? true
        glassClarity = d.object(forKey: "glassClarity") as? Double ?? 0.6
        expandedWidth = d.object(forKey: "expandedWidth") as? Double ?? 720
        expandedHeight = d.object(forKey: "expandedHeight") as? Double ?? 240
        cornerRadius = d.object(forKey: "cornerRadius") as? Double ?? 30
        accent = d.object(forKey: "accent") as? String ?? "blue"
        showMusicWings = d.object(forKey: "showMusicWings") as? Bool ?? true
        closeDelay = d.object(forKey: "closeDelay") as? Double ?? 0.35
        rememberTab = d.object(forKey: "rememberTab") as? Bool ?? true
        fahrenheit = d.object(forKey: "fahrenheit") as? Bool ?? false
        clipboardLimit = d.object(forKey: "clipboardLimit") as? Double ?? 30
        hdrMax = d.object(forKey: "hdrMax") as? Double ?? 1.6
        timerSound = d.object(forKey: "timerSound") as? Bool ?? true
        effort = d.object(forKey: "effort") as? String ?? "low"
        customInstructions = d.object(forKey: "customInstructions") as? String ?? ""
        memory = d.stringArray(forKey: "memory") ?? []
        tickerSymbols = d.string(forKey: "tickerSymbols") ?? "BTCUSDT, ETHUSDT"
        theme = d.string(forKey: "theme") ?? "aurora"
        color1 = d.string(forKey: "color1") ?? "#7B5CFF"
        color2 = d.string(forKey: "color2") ?? "#00D4FF"
        warmth = d.object(forKey: "warmth") as? Double ?? 0
        contrast = d.object(forKey: "contrast") as? Double ?? 0
        dim = d.object(forKey: "dim") as? Double ?? 0
        showMeeting = d.object(forKey: "showMeeting") as? Bool ?? true
        pomodoroWork = d.object(forKey: "pomodoroWork") as? Double ?? 25
        pomodoroBreak = d.object(forKey: "pomodoroBreak") as? Double ?? 5
        pinnedApps = d.stringArray(forKey: "pinnedApps") ?? [
            "/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Notes.app",
            "/System/Applications/Calendar.app", "/System/Applications/Music.app",
            "/System/Applications/Utilities/Terminal.app", "/System/Applications/System Settings.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }

    static let accents: [(id: String, name: String, color: Color)] = [
        ("blue", L("Mavi"), .blue), ("purple", L("Mor"), .purple), ("pink", L("Pembe"), .pink), ("red", L("Kırmızı"), .red),
        ("orange", L("Turuncu"), .orange), ("green", L("Yeşil"), .green), ("teal", L("Camgöbeği"), .teal), ("graphite", L("Grafit"), Color(white: 0.6)),
    ]
    static let themes: [(id: String, name: String)] = [
        ("aurora", "Aurora"), ("neon", "Neon"), ("gradient", L("Gradyan")), ("glass", L("Cam")), ("black", L("Siyah")),
    ]
    var themeColor1: Color { Color(hex: color1) ?? .purple }
    var themeColor2: Color { Color(hex: color2) ?? .cyan }

    private func tuningChanged() {
        DispatchQueue.main.async { BoostService.shared.refresh() }
    }

    var accentColor: Color { Self.accents.first { $0.id == accent }?.color ?? .blue }

    /// Sıcaklığı seçili birimde tam sayı olarak verir.
    func temp(_ celsius: Double) -> Int { Int((fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded()) }

    func isOn(_ m: ModuleID) -> Bool { modules[m.rawValue] ?? !ModuleID.defaultOff.contains(m) }
    func set(_ m: ModuleID, _ on: Bool) { modules[m.rawValue] = on }
    func binding(_ m: ModuleID) -> Binding<Bool> {
        Binding(get: { self.isOn(m) }, set: { self.set(m, $0) })
    }
}

// MARK: - Çentik durumu

enum NotchTab: String, CaseIterable, Identifiable {
    case home, assistant, tools, shelf, apps, mirror
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .assistant: return "sparkles"
        case .tools: return "square.grid.2x2.fill"
        case .shelf: return "tray.full.fill"
        case .apps: return "square.grid.3x3.fill"
        case .mirror: return "person.crop.square.fill"
        }
    }
    var title: String {
        switch self {
        case .home: return L("Ana")
        case .assistant: return L("Asistan")
        case .tools: return L("Araçlar")
        case .shelf: return L("Raf")
        case .apps: return L("Uygulamalar")
        case .mirror: return L("Ayna")
        }
    }
}

struct HUDInfo: Equatable {
    var icon: String
    var title: String
    var value: Double? = nil
    var label: String? = nil
    var tint: Color = .white
}

final class NotchModel: ObservableObject {
    static let shared = NotchModel()

    @Published var expanded = false
    @Published var tab: NotchTab = .home
    @Published var hud: HUDInfo?
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var dropTargeted = false
    @Published var focusInput = 0

    var expandedSize: CGSize { CGSize(width: Prefs.shared.expandedWidth, height: Prefs.shared.expandedHeight) }
    private var hudToken = 0

    var availableTabs: [NotchTab] {
        let p = Prefs.shared
        var t: [NotchTab] = [.home]
        if p.isOn(.assistant) { t.append(.assistant) }
        if p.isOn(.timer) || p.isOn(.clipboard) || p.isOn(.notes) || p.isOn(.stats) { t.append(.tools) }
        if p.isOn(.shelf) { t.append(.shelf) }
        if p.isOn(.launcher) { t.append(.apps) }
        if p.isOn(.mirror) { t.append(.mirror) }
        return t
    }

    var compactMeeting: Bool {
        Prefs.shared.isOn(.calendar) && Prefs.shared.showMeeting && AgendaService.shared.next != nil
    }
    var compactDownload: Bool { Prefs.shared.isOn(.downloads) && DownloadsService.shared.current != nil }
    var compactPrivacy: Bool { Prefs.shared.isOn(.privacy) && PrivacyService.shared.anyOn }
    var compactTimer: Bool { Prefs.shared.isOn(.timer) && CountdownService.shared.running }
    var compactMusic: Bool { Prefs.shared.isOn(.music) && Prefs.shared.showMusicWings && MusicService.shared.isPlaying }

    func currentSize() -> CGSize {
        if expanded { return expandedSize }
        if hud != nil { return CGSize(width: notchSize.width + 2 * 118, height: notchSize.height) }
        var wing: CGFloat = 0
        if compactPrivacy { wing = 30 }
        if compactMusic { wing = 46 }
        if compactDownload { wing = 76 }
        if compactMeeting { wing = 72 }
        if compactTimer { wing = 68 }
        if compactPrivacy, wing > 30 { wing += 12 }
        return CGSize(width: notchSize.width + 2 * wing, height: notchSize.height)
    }

    func showHUD(_ info: HUDInfo, seconds: Double = 2.0) {
        hudToken += 1
        let token = hudToken
        hud = info
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.hudToken == token else { return }
            self.hud = nil
        }
    }

    func expand(tab: NotchTab? = nil) {
        if let tab, availableTabs.contains(tab) { self.tab = tab }
        else if tab == nil, !expanded, !Prefs.shared.rememberTab { self.tab = .home }
        if !availableTabs.contains(self.tab) { self.tab = .home }
        guard !expanded else { return }
        expanded = true
        if Prefs.shared.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func collapse() {
        guard expanded else { return }
        expanded = false
    }
}

// MARK: - Yardımcılar

extension Color {
    /// "#RRGGBB" biçiminden renk.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 15) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return (p.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}

enum Script {
    /// NSAppleScript tek bir seri kuyrukta çalıştırılır.
    static let queue = DispatchQueue(label: "ada.applescript")

    static func runSync(_ source: String) -> (out: NSAppleEventDescriptor?, err: String?) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return (nil, L("Betik oluşturulamadı")) }
        let result = script.executeAndReturnError(&error)
        if let error {
            return (nil, (error[NSAppleScript.errorMessage] as? String) ?? L("AppleScript hatası"))
        }
        return (result, nil)
    }

    static func run(_ source: String) async -> (out: String?, err: String?) {
        await withCheckedContinuation { cont in
            queue.async {
                let r = runSync(source)
                cont.resume(returning: (r.out?.stringValue ?? (r.err == nil ? "" : nil), r.err))
            }
        }
    }

    static func fire(_ source: String) {
        queue.async { _ = runSync(source) }
    }
}

extension String {
    var appleScriptQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

func formatClock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Modül yöneticisi

final class ModuleManager {
    static let shared = ModuleManager()
    private var bag = Set<AnyCancellable>()

    func start() {
        apply()
        BoostService.shared.refresh()
        Prefs.shared.$modules
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &bag)
    }

    func apply() {
        let p = Prefs.shared
        MusicService.shared.setEnabled(p.isOn(.music))
        AgendaService.shared.setEnabled(events: p.isOn(.calendar), reminders: p.isOn(.reminders))
        WeatherService.shared.setEnabled(p.isOn(.weather))
        BatteryService.shared.setEnabled(p.isOn(.battery))
        BluetoothService.shared.setEnabled(p.isOn(.bluetooth))
        HUDService.shared.setEnabled(p.isOn(.hud))
        MediaKeyTap.shared.setEnabled(p.isOn(.hud))
        if !p.isOn(.xdr) { BoostService.shared.set(1) }
        StatsService.shared.setEnabled(p.isOn(.stats))
        ClipboardService.shared.setEnabled(p.isOn(.clipboard))
        PrivacyService.shared.setEnabled(p.isOn(.privacy))
        DownloadsService.shared.setEnabled(p.isOn(.downloads))
        NetworkService.shared.setEnabled(p.isOn(.network))
        TickerService.shared.setEnabled(p.isOn(.ticker))
        CapsLockMonitor.shared.setEnabled(p.isOn(.hud))
        let model = NotchModel.shared
        if !model.availableTabs.contains(model.tab) { model.tab = .home }
    }
}
