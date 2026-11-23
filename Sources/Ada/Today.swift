import AppKit
import SwiftUI

// MARK: - Uygulama kullanımı

/// Hangi uygulamanın ne kadar süre önde olduğunu kaydeder. Veriler yalnızca bu Mac'te tutulur.
final class AppUsage: ObservableObject {
    static let shared = AppUsage()

    struct Entry: Identifiable {
        var id: String { bundle }
        var bundle: String
        var name: String
        var seconds: Double
    }

    @Published private(set) var today: [Entry] = []

    private var log: [String: [String: Double]]
    private var names: [String: String]
    private var current: (bundle: String, name: String)?
    private var since = Date()
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    private init() {
        log = (UserDefaults.standard.dictionary(forKey: "appUsage") as? [String: [String: Double]]) ?? [:]
        names = (UserDefaults.standard.dictionary(forKey: "appUsageNames") as? [String: String]) ?? [:]
    }

    private static func key(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            since = Date()
            noteFront(NSWorkspace.shared.frontmostApplication)
            observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                self?.flush()
                self?.noteFront(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.flush() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            publish()
        } else if !on {
            flush()
            timer?.invalidate(); timer = nil
            if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            observer = nil
        }
    }

    private func noteFront(_ app: NSRunningApplication?) {
        guard let app, let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier else {
            current = nil
            return
        }
        current = (bundle, app.localizedName ?? bundle)
    }

    private func flush() {
        let now = Date()
        let elapsed = now.timeIntervalSince(since)
        since = now
        guard let current, elapsed > 0, elapsed < 120 else { return }
        // Beş dakikadır klavye/fare kullanılmadıysa bilgisayar başında değilsiniz; sayma.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard idle < 300 else { return }
        let day = Self.key(now)
        log[day, default: [:]][current.bundle, default: 0] += elapsed
        names[current.bundle] = current.name
        if log.count > 15 {
            let cutoff = Self.key(now.addingTimeInterval(-14 * 86400))
            log = log.filter { $0.key >= cutoff }
        }
        UserDefaults.standard.set(log, forKey: "appUsage")
        UserDefaults.standard.set(names, forKey: "appUsageNames")
        publish()
    }

    private func publish() {
        let day = log[Self.key(Date())] ?? [:]
        today = day.map { Entry(bundle: $0.key, name: names[$0.key] ?? $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    static func text(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        if m < 1 { return L("1 dk'dan az") }
        return m >= 60 ? Lf("%@ sa %@ dk", "\(m / 60)", "\(m % 60)") : Lf("%@ dk", "\(m)")
    }
}

// MARK: - Sistem ayrıntıları

final class SystemInfo: ObservableObject {
    static let shared = SystemInfo()

    struct Snapshot {
        var cycles: Int?
        var health: Int?
        var temperature: Double?
        var diskFree: Double = 0
        var diskTotal: Double = 0
        var top: [(name: String, cpu: Double)] = []
    }

    @Published var snapshot = Snapshot()
    private var loading = false

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let s = Self.collect()
            DispatchQueue.main.async {
                self.snapshot = s
                self.loading = false
            }
        }
    }

    /// Yavaş olabilir (ioreg ve ps çağırır); ana iş parçacığı dışında çağrılmalı.
    static func collect() -> Snapshot {
        var s = Snapshot()
        let io = Shell.run("/usr/sbin/ioreg", ["-rc", "AppleSmartBattery"], timeout: 8).out
        // Anahtarlar hem "Ad" = 12 hem "Ad"=12 biçiminde yazılabiliyor.
        func int(_ key: String) -> Int? {
            guard let re = try? NSRegularExpression(pattern: "\"\(key)\"\\s?=\\s?(\\d+)"),
                  let m = re.firstMatch(in: io, range: NSRange(io.startIndex..., in: io)),
                  let r = Range(m.range(at: 1), in: io) else { return nil }
            return Int(io[r])
        }
        s.cycles = int("CycleCount")
        if let raw = int("AppleRawMaxCapacity"), let design = int("DesignCapacity"), design > 0 {
            s.health = min(100, Int((Double(raw) / Double(design) * 100).rounded()))
        }
        if let t = int("Temperature"), t > 0 { s.temperature = Double(t) / 100 }

        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            s.diskFree = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
            s.diskTotal = Double(v.volumeTotalCapacity ?? 0)
        }

        let ps = Shell.run("/bin/ps", ["-Aceo", "pcpu,comm", "-r"], timeout: 8).out
        for line in ps.components(separatedBy: "\n").dropFirst().prefix(4) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let cpu = Double(trimmed[..<space].replacingOccurrences(of: ",", with: ".")) else { continue }
            let name = trimmed[space...].trimmingCharacters(in: .whitespaces)
            if name != "Ada" { s.top.append((name, cpu)) }
        }
        s.top = Array(s.top.prefix(3))
        return s
    }
}

// MARK: - Bildirim geçmişi (çentikte gösterilenler)

struct HUDLogItem: Identifiable {
    let id = UUID()
    var icon: String
    var text: String
    var date: Date
}

// MARK: - "Bugün" sekmesi

struct TodayView: View {
    @ObservedObject var usage = AppUsage.shared
    @ObservedObject var info = SystemInfo.shared
    @ObservedObject var model = NotchModel.shared
    @ObservedObject var focus = FocusStats.shared

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            usageColumn.frame(maxWidth: .infinity, alignment: .topLeading)
            systemColumn.frame(maxWidth: .infinity, alignment: .topLeading)
            logColumn.frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { info.refresh() }
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in info.refresh() }
    }

    private var usageColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionTitle(text: L("Uygulama kullanımı"))
            if !Opt.flag("today.usage") {
                hint(L("Kullanım kaydı kapalı."))
            } else if usage.today.isEmpty {
                hint(L("Bugün için henüz veri yok."))
            } else {
                let top = usage.today.first?.seconds ?? 1
                ForEach(usage.today.prefix(Prefs.shared.compact ? 4 : 5)) { e in
                    HStack(spacing: 6) {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundle) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 15, height: 15)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(e.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(AppUsage.text(e.seconds)).foregroundStyle(.white.opacity(0.55))
                            }
                            .font(.system(size: 10.5).monospacedDigit())
                            GeometryReader { geo in
                                Capsule().fill(Prefs.shared.accentColor.opacity(0.8))
                                    .frame(width: max(3, geo.size.width * CGFloat(e.seconds / top)))
                            }
                            .frame(height: 3)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var systemColumn: some View {
        let s = info.snapshot
        return VStack(alignment: .leading, spacing: 5) {
            SectionTitle(text: L("Sistem"))
            if let health = s.health {
                row("battery.100", L("Pil sağlığı"), "%\(health)" + (s.cycles.map { " · " + Lf("%@ döngü", "\($0)") } ?? ""))
            }
            if let t = s.temperature { row("thermometer.medium", L("Pil sıcaklığı"), String(format: "%.0f°C", t)) }
            if s.diskTotal > 0 {
                row("internaldrive", L("Boş disk"), String(format: "%.0f / %.0f GB", s.diskFree / 1e9, s.diskTotal / 1e9))
            }
            row("brain.head.profile", L("Bugün odak"), FocusStats.text(focus.today))
            if !s.top.isEmpty {
                SectionTitle(text: L("En çok işlemci kullanan")).padding(.top, 3)
                ForEach(Array(s.top.prefix(Prefs.shared.compact ? 2 : 3).enumerated()), id: \.offset) { _, p in
                    HStack {
                        Text(p.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(String(format: "%%%.0f", p.cpu)).foregroundStyle(.white.opacity(0.55))
                    }
                    .font(.system(size: 10.5).monospacedDigit())
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var logColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionTitle(text: L("Son bildirimler"))
            if model.hudLog.isEmpty {
                hint(L("Çentikte gösterilen bildirimler burada listelenir."))
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.hudLog.reversed()) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: item.icon).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).frame(width: 14)
                                Text(item.text).font(.system(size: 10.5)).lineLimit(2)
                                Spacer(minLength: 4)
                                Text(Self.clock(item.date)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).frame(width: 14)
            Text(title).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 4)
            Text(value).fontWeight(.semibold)
        }
        .font(.system(size: 10.5).monospacedDigit())
        .lineLimit(1)
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
    }

    private static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Yapılacaklar

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
}

final class TodoStore: ObservableObject {
    static let shared = TodoStore()
    @Published var items: [TodoItem] { didSet { save() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "todos"), let list = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = list
        } else {
            items = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: "todos") }
    }

    func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(TodoItem(text: t))
    }

    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].done.toggle()
    }

    /// Başlığında verilen metin geçen ilk öğe.
    func index(matching text: String) -> Int? {
        items.firstIndex { $0.text.localizedCaseInsensitiveContains(text) }
    }
}

struct TodoListView: View {
    @ObservedObject var store = TodoStore.shared
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 5) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.items) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Button { withAnimation(.easeInOut(duration: 0.15)) { store.toggle(item.id) } } label: {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(item.done ? Color.green : .white.opacity(0.55))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.plain)
                            Text(item.text)
                                .font(.system(size: 11.5))
                                .strikethrough(item.done)
                                .foregroundStyle(item.done ? .white.opacity(0.4) : .white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contextMenu {
                            Button(L("Sil")) { store.items.removeAll { $0.id == item.id } }
                        }
                    }
                    if store.items.isEmpty {
                        Text(L("Liste boş. Aşağıya yazıp Enter'a basın.")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                TextField(L("Yeni madde…"), text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 11.5))
                    .onSubmit { store.add(draft); draft = "" }
                    .onTapGesture { NotchController.shared.makeKey() }
                if store.items.contains(where: \.done) {
                    Button { store.items.removeAll { $0.done } } label: {
                        Image(systemName: "checkmark.circle.badge.xmark").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(HoverIconStyle()).help(L("Tamamlananları temizle"))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .glassCard(Capsule())
        }
    }
}

// MARK: - Başlatıcı: uygulama, dosya, bağlantı ve kestirmeler

enum LauncherEntry {
    case file(String)
    case link(URL)
    case shortcut(String)

    init(_ raw: String) {
        if raw.hasPrefix("shortcut:") {
            self = .shortcut(String(raw.dropFirst("shortcut:".count)))
        } else if raw.hasPrefix("url:"), let u = URL(string: String(raw.dropFirst("url:".count))) {
            self = .link(u)
        } else {
            self = .file(raw)
        }
    }

    var title: String {
        switch self {
        case let .file(path): return FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        case let .link(url): return url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        case let .shortcut(name): return name
        }
    }

    func open() {
        switch self {
        case let .file(path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case let .link(url):
            NSWorkspace.shared.open(url)
        case let .shortcut(name):
            NotchModel.shared.showHUD(HUDInfo(icon: "square.2.layers.3d.fill", title: name, leftText: L("Kestirme"), wide: true, tint: .pink), seconds: 2)
            DispatchQueue.global().async {
                let r = Shell.run("/usr/bin/shortcuts", ["run", name], timeout: 120)
                guard r.code != 0 else { return }
                DispatchQueue.main.async {
                    NotchModel.shared.showHUD(HUDInfo(icon: "exclamationmark.triangle.fill", title: L("Kestirme çalışmadı"), tint: .orange), seconds: 3)
                }
            }
        }
    }
}

struct LauncherView: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: L("Uygulamalar"))
                Spacer()
                Menu {
                    Button(L("Uygulama, dosya ya da klasör…")) { addFile() }
                    Button(L("Bağlantı…")) { addLink() }
                    Button(L("Kestirme…")) { addShortcut() }
                } label: {
                    Label(L("Ekle"), systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(PillButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if prefs.pinnedApps.isEmpty {
                EmptyHint(icon: "square.grid.3x3", text: L("Sık kullandığınız uygulamaları \"Ekle\" ile sabitleyin."))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(prefs.pinnedApps, id: \.self) { raw in
                            let entry = LauncherEntry(raw)
                            Button {
                                entry.open()
                                if Opt.flag("launcher.close") { NotchController.shared.close() }
                            } label: {
                                VStack(spacing: 4) {
                                    icon(entry).frame(width: Opt.num("launcher.icon"), height: Opt.num("launcher.icon"))
                                    Text(entry.title).font(.system(size: 10)).lineLimit(1).frame(width: 70)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(HoverIconStyle())
                            .contextMenu {
                                Button(L("Başlatıcıdan Kaldır")) { prefs.pinnedApps.removeAll { $0 == raw } }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private func icon(_ entry: LauncherEntry) -> some View {
        switch entry {
        case let .file(path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)).resizable()
        case .link:
            symbolTile("globe", [.blue, .cyan])
        case .shortcut:
            symbolTile("square.2.layers.3d.fill", [.pink, .purple])
        }
    }

    private func symbolTile(_ symbol: String, _ colors: [Color]) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: geo.size.width * 0.24, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Image(systemName: symbol).font(.system(size: geo.size.width * 0.46, weight: .semibold)).foregroundStyle(.white))
                .padding(geo.size.width * 0.06)
        }
    }

    private func append(_ raw: String) {
        if !prefs.pinnedApps.contains(raw) { prefs.pinnedApps.append(raw) }
    }

    private func addFile() {
        NotchController.shared.close()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Sabitle")
        if panel.runModal() == .OK { panel.urls.forEach { append($0.path) } }
    }

    private func addLink() {
        NotchController.shared.close()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Bağlantı ekle")
        alert.informativeText = L("Çentikten açmak istediğiniz adresi yazın.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "https://"
        alert.accessoryView = field
        alert.addButton(withTitle: L("Ekle"))
        alert.addButton(withTitle: L("Vazgeç"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if !text.contains("://") { text = "https://" + text }
        if let url = URL(string: text), url.host != nil { append("url:" + url.absoluteString) }
    }

    private func addShortcut() {
        NotchController.shared.close()
        DispatchQueue.global().async {
            let names = Shell.run("/usr/bin/shortcuts", ["list"], timeout: 15).out.components(separatedBy: "\n").filter { !$0.isEmpty }
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = L("Kestirme ekle")
                guard !names.isEmpty else {
                    alert.informativeText = L("Kestirmeler uygulamasında kestirme bulunamadı.")
                    alert.runModal()
                    return
                }
                alert.informativeText = L("Çentikten çalıştırmak istediğiniz kestirmeyi seçin.")
                let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
                popup.addItems(withTitles: names)
                alert.accessoryView = popup
                alert.addButton(withTitle: L("Ekle"))
                alert.addButton(withTitle: L("Vazgeç"))
                if alert.runModal() == .alertFirstButtonReturn, let name = popup.titleOfSelectedItem { self.append("shortcut:" + name) }
            }
        }
    }
}

// MARK: - Günlük hava tahmini

struct DayForecast: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var high: Double
    var low: Double
    var code: Int
    var rain: Int
}

struct ForecastStrip: View {
    @ObservedObject var weather = WeatherService.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var daily = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                SectionTitle(text: daily ? L("Günlük tahmin") : L("Saatlik tahmin"))
                Spacer()
                Button(daily ? L("Saatlik") : L("Günlük")) { withAnimation(.easeInOut(duration: 0.2)) { daily.toggle() } }
                    .buttonStyle(PillButtonStyle())
            }
            if daily {
                cells(weather.daily.prefix(5).map { d in
                    (label: Self.day(d.date), symbol: WeatherNow(temperature: 0, code: d.code, isDay: true, place: "").symbol,
                     main: "\(prefs.temp(d.high))°", sub: "\(prefs.temp(d.low))°", rain: d.rain)
                })
            } else {
                cells(weather.hourly.prefix(max(4, Int(Opt.num("weather.hours")))).map { h in
                    (label: Self.hour(h.time), symbol: WeatherNow(temperature: 0, code: h.code, isDay: h.isDay, place: "").symbol,
                     main: "\(prefs.temp(h.temperature))°", sub: "", rain: h.rain)
                })
            }
        }
    }

    @ViewBuilder
    private func cells(_ items: [(label: String, symbol: String, main: String, sub: String, rain: Int)]) -> some View {
        if items.isEmpty {
            Text(L("Tahmin yükleniyor…")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
        } else {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 2) {
                        Text(item.label).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                        Image(systemName: item.symbol).symbolRenderingMode(.multicolor).font(.system(size: 15)).frame(height: 18)
                        HStack(spacing: 3) {
                            Text(item.main).font(.system(size: 11.5, weight: .semibold))
                            if !item.sub.isEmpty { Text(item.sub).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)) }
                        }
                        Text(item.rain > 0 && Opt.flag("weather.rain") ? "%\(item.rain)" : " ").font(.system(size: 9)).foregroundStyle(.cyan)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private static func hour(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private static func day(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return L("Bugün") }
        let f = DateFormatter()
        f.locale = appLocale
        f.dateFormat = "EEE"
        return f.string(from: d)
    }
}

// MARK: - Tam ekran algılama

enum Fullscreen {
    /// Öndeki uygulama tam ekrandaysa true: menü çubuğu görünmüyor ve uygulamanın penceresi ekranı enine kaplıyor.
    static func active(on screen: NSScreen) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        var menuBarVisible = false
        var wide = false
        for w in list {
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            if layer == Int(CGWindowLevelForKey(.mainMenuWindow)), (w[kCGWindowOwnerName as String] as? String) == "Window Server" { menuBarVisible = true }
            if layer == 0, (w[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
               (bounds["Width"] ?? 0) >= screen.frame.width - 1, (bounds["Height"] ?? 0) >= screen.frame.height - 60 { wide = true }
        }
        return wide && !menuBarVisible
    }
}
