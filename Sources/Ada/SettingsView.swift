import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case modules, appearance, assistant, general, permissions, updates
    var id: String { rawValue }

    var title: String {
        switch self {
        case .modules: return L("Modüller")
        case .appearance: return L("Görünüm")
        case .assistant: return L("Asistan")
        case .general: return L("Genel")
        case .permissions: return L("İzinler")
        case .updates: return L("Güncellemeler")
        }
    }

    var icon: String {
        switch self {
        case .modules: return "square.grid.2x2.fill"
        case .appearance: return "paintbrush.fill"
        case .assistant: return "sparkles"
        case .general: return "gearshape.fill"
        case .permissions: return "hand.raised.fill"
        case .updates: return "arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .modules: return .blue
        case .appearance: return .purple
        case .assistant: return .orange
        case .general: return .gray
        case .permissions: return .red
        case .updates: return .green
        }
    }
}

struct SettingsView: View {
    /// İlk açılışta İzinler sayfası gösterilir.
    static var initialPage: SettingsPage = .modules
    @State private var page: SettingsPage = SettingsView.initialPage
    @ObservedObject var updater = Updater.shared
    @ObservedObject var prefs = Prefs.shared
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                Text(page.title)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.top, 18)
                    .padding(.bottom, 2)
                Group {
                    switch page {
                    case .modules: ModulesSettings()
                    case .appearance: AppearanceSettings()
                    case .assistant: AssistantSettings()
                    case .general: GeneralSettings()
                    case .permissions: PermissionsSettings()
                    case .updates: UpdatesSettings()
                    }
                }
                .id(page)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 600)
        .animation(.easeInOut(duration: 0.18), value: page)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                AppBadge(size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ada").font(.headline)
                    Text(Lf("Sürüm %@", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 44)
            .padding(.bottom, 14)

            ForEach(SettingsPage.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(item.color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(item.title).font(.system(size: 13, weight: page == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if item == .updates, updater.updateAvailable {
                            Circle().fill(.blue).frame(width: 8, height: 8)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background {
                        if page == item {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.1))
                                .matchedGeometryEffect(id: "page", in: selection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { NotchController.shared.preview() } label: {
                Label(L("Çentiği önizle"), systemImage: "eye")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 10)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

struct ModulesSettings: View {
    @ObservedObject var prefs = Prefs.shared

    private let groups: [(String, Color, [ModuleID])] = [
        (L("Ana sekme"), .pink, [.music, .lyrics, .calendar, .reminders, .weather, .ticker, .clocks]),
        (L("Canlı bildirimler ve ekran"), .orange, [.battery, .bluetooth, .hud, .xdr, .privacy, .network, .downloads]),
        (L("Araçlar"), .blue, [.timer, .breaks, .clipboard, .notes, .stats, .today, .shelf, .screenshots, .launcher, .mirror]),
        (L("Asistan"), .purple, [.assistant]),
        (L("Gelişmiş (ek izin gerektirir)"), .gray, [.focus, .notifications, .visualizer, .lockscreen]),
    ]

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            let on = group.2.filter { prefs.isOn($0) }.count
                            Text("\(on)/\(group.2.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(group.2) { m in
                                ModuleCard(module: m, color: group.1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
        .safeAreaInset(edge: .bottom) {
            if prefs.isOn(.focus) || prefs.isOn(.notifications) {
                FullDiskBanner()
            }
        }
    }
}

struct ModuleCard: View {
    var module: ModuleID
    var color: Color
    @ObservedObject var prefs = Prefs.shared
    @State private var hover = false
    @State private var showOptions = false

    var body: some View {
        let on = prefs.isOn(module)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: module.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background((on ? color : Color.gray).gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(module.detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("", isOn: prefs.binding(module)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                if Opt.all[module] != nil {
                    Button { showOptions = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 20)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(L("İnce ayarlar"))
                    .popover(isPresented: $showOptions, arrowEdge: .trailing) { ModuleOptionsView(module: module) }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(Color.primary.opacity(hover ? 0.09 : 0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(on ? color.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { prefs.set(module, !on) }
        .onHover { hover = $0 }
        .animation(.easeInOut(duration: 0.15), value: hover)
        .animation(.easeInOut(duration: 0.2), value: on)
        .help(module.detail)
    }
}

/// Tema seçimi: her temanın küçük bir önizlemesi.
struct ThemePicker: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Prefs.themes, id: \.id) { theme in
                let selected = prefs.theme == theme.id
                Button { prefs.theme = theme.id } label: {
                    VStack(spacing: 6) {
                        preview(theme.id)
                            .frame(height: 46)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2.5 : 1))
                        Text(theme.name).font(.system(size: 11, weight: selected ? .semibold : .regular))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.15), value: prefs.theme)
    }

    @ViewBuilder private func preview(_ id: String) -> some View {
        let c1 = prefs.themeColor1, c2 = prefs.themeColor2
        ZStack {
            // Arka planda bir masaüstünü andıran zemin
            LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)], startPoint: .top, endPoint: .bottom)
            switch id {
            case "aurora":
                Color.black.opacity(0.55)
                RadialGradient(colors: [c1.opacity(0.9), .clear], center: .bottomLeading, startRadius: 0, endRadius: 60)
                RadialGradient(colors: [c2.opacity(0.9), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 60)
            case "neon":
                Color.black.opacity(0.85)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AngularGradient(colors: [c1, c2, c1], center: .center), lineWidth: 3)
            case "gradient":
                LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.9)
            case "glass":
                Color.black.opacity(0.35)
                LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
            default:
                Color.black
            }
        }
    }
}

/// Odak modu ve bildirimler için Tam Disk Erişimi durumunu gösterir.
struct FullDiskBanner: View {
    @State private var granted = FullDiskAccess.granted
    @ObservedObject var notifications = NotificationWatcher.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(granted ? (notifications.problem ?? L("Tam Disk Erişimi verildi.")) : L("Odak modu ve bildirimler için Tam Disk Erişimi gerekli. İzni verdikten sonra Ada'yı yeniden başlatın."))
                .font(.callout)
            Spacer()
            if !granted { Button(L("Ayarı aç")) { FullDiskAccess.openSettings() } }
        }
        .padding(10)
        .background(.bar)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in granted = FullDiskAccess.granted }
    }
}

struct AssistantSettings: View {
    @ObservedObject var prefs = Prefs.shared
    @State private var key = ""
    @State private var saved = (Keychain.get() ?? "").isEmpty == false

    var body: some View {
        Form {
            Section {
                HStack {
                    SecureField("sk-ant-…", text: $key)
                        .textFieldStyle(.roundedBorder)
                    Button(L("Kaydet")) {
                        Keychain.set(key)
                        key = ""
                        saved = (Keychain.get() ?? "").isEmpty == false
                        AssistantEngine.shared.refreshKey()
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Label(saved ? L("Anahtar kayıtlı (Anahtar Zinciri'nde saklanıyor)") : L("Henüz anahtar yok"),
                          systemImage: saved ? "checkmark.seal.fill" : "key")
                        .foregroundStyle(saved ? .green : .secondary)
                        .font(.callout)
                    Spacer()
                    if saved {
                        Button(L("Sil"), role: .destructive) {
                            Keychain.set("")
                            saved = false
                            AssistantEngine.shared.refreshKey()
                        }
                    }
                }
            } header: {
                Text(L("Anthropic API anahtarı"))
            } footer: {
                Text(L("Anahtarı console.anthropic.com adresinden alabilirsiniz. Yalnızca bu Mac'in Anahtar Zinciri'nde saklanır ve yalnızca api.anthropic.com'a gönderilir."))
            }

            Section(L("Model ve ses")) {
                Picker("Model", selection: $prefs.model) {
                    ForEach(ClaudeClient.models, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker(L("Konuşma dili"), selection: $prefs.speechLocale) {
                    Text("Türkçe").tag("tr-TR")
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Deutsch").tag("de-DE")
                }
                Toggle(L("Yanıtları sesli oku"), isOn: $prefs.speakReplies)
                Picker(L("Yanıt biçimi"), selection: $prefs.effort) {
                    Text(L("Hızlı")).tag("low")
                    Text(L("Dengeli")).tag("medium")
                    Text(L("Derinlemesine (yavaş, pahalı)")).tag("high")
                }
            }

            Section {
                TextEditor(text: $prefs.customInstructions)
                    .font(.body)
                    .frame(height: 70)
            } header: {
                Text(L("Özel talimatlar"))
            } footer: {
                Text(L("Asistanın her sohbette uymasını istediğiniz kurallar. Örnek: \"Bana sen diye hitap et, yanıtları tek cümle tut.\""))
            }

            ScheduledTasksSection()
            CommandsSection()

            Section {
                if prefs.memory.isEmpty {
                    Text(L("Henüz kayıtlı bir şey yok. Asistana \"şunu hatırla…\" diyebilirsiniz."))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.memory, id: \.self) { item in
                        HStack {
                            Text(item)
                            Spacer()
                            Button { prefs.memory.removeAll { $0 == item } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text(L("Hafıza"))
            } footer: {
                Text(L("Asistanın sizin hakkınızda hatırladıkları. Yalnızca bu Mac'te saklanır ve her sohbette Claude'a gönderilir."))
            }

            Section {
                Toggle(isOn: $prefs.allowWeb) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Web araması"))
                        Text(L("Asistan güncel bilgi için internette arama yapabilir (Anthropic tarafında çalışır, ek ücretlidir)."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $prefs.allowScreen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Ekrana bakabilsin"))
                        Text(L("İstediğinizde ekran görüntüsü alıp Claude'a gönderir. macOS ekran kaydı izni ister."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $prefs.allowAppleScript) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("AppleScript çalıştırabilsin"))
                        Text(L("Diğer araçların yapamadığı işler için. Her betik çalışmadan önce size gösterilir ve onayınız istenir."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("Asistanın yetkileri"))
            } footer: {
                Text(L("Takvim, anımsatıcı, müzik, ses, parlaklık, görünüm, uygulama açma/kapama, zamanlayıcı, pano, not ve Ada modülleri her zaman kullanılabilir."))
            }
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettings: View {
    @ObservedObject var prefs = Prefs.shared
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @ObservedObject var boost = BoostService.shared
    @State private var trusted = MediaKeyTap.shared.trusted

    var body: some View {
        Form {
            Section(L("Çentik")) {
                Toggle(L("Fareyle üzerine gelince aç"), isOn: $prefs.openOnHover)
                if prefs.openOnHover {
                    HStack {
                        Text(L("Açılma gecikmesi"))
                        Slider(value: $prefs.hoverDelay, in: 0...0.8)
                        Text(String(format: L("%.2f sn"), prefs.hoverDelay)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                } else {
                    Text(L("Kapalıyken çentiğe tıklayarak açılır.")).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(L("Kapanma gecikmesi"))
                    Slider(value: $prefs.closeDelay, in: 0.1...2)
                    Text(String(format: L("%.1f sn"), prefs.closeDelay)).monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                Toggle(L("Son açık sekmeyi hatırla"), isOn: $prefs.rememberTab)
                Toggle(L("Açılırken dokunsal geri bildirim"), isOn: $prefs.haptics)
                Toggle(L("Animasyonları azalt (konfeti, yazı efekti, ışıltı)"), isOn: $prefs.reduceMotion)
                Toggle(L("İki parmakla kaydırma hareketleri"), isOn: $prefs.gestures)
                Toggle(L("Tam ekran uygulamalarda gizlen"), isOn: $prefs.hideInFullscreen)
                ScreenPicker()
            }
            Section(L("Modül ayarları")) {
                Picker(L("Sıcaklık birimi"), selection: $prefs.fahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                HStack {
                    Text(L("Pano geçmişi"))
                    Slider(value: $prefs.clipboardLimit, in: 10...100, step: 10)
                    Text(Lf("%@ öğe", "\(Int(prefs.clipboardLimit))")).monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                Toggle(L("Zamanlayıcı bitince ses çal"), isOn: $prefs.timerSound)
                HStack {
                    Text(L("Piyasa sembolleri"))
                    TextField("BTCUSDT, ETHUSDT", text: $prefs.tickerSymbols)
                        .textFieldStyle(.roundedBorder)
                }
                Stepper(Lf("Pomodoro odak süresi: %@ dk", "\(Int(prefs.pomodoroWork))"), value: $prefs.pomodoroWork, in: 5...90, step: 5)
                Stepper(Lf("Pomodoro mola süresi: %@ dk", "\(Int(prefs.pomodoroBreak))"), value: $prefs.pomodoroBreak, in: 1...30, step: 1)
                HStack {
                    Text(L("HDR üst sınırı"))
                    Slider(value: $prefs.hdrMax, in: 1.2...1.6, step: 0.1)
                    Text("%\(Int((prefs.hdrMax * 100).rounded()))").monospacedDigit().frame(width: 64, alignment: .trailing)
                }
            }
            Section {
                HStack {
                    Label(trusted ? L("Erişilebilirlik izni verildi") : L("Erişilebilirlik izni yok"),
                          systemImage: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Spacer()
                    if !trusted {
                        Button(L("İzin iste")) { MediaKeyTap.shared.requestTrust() }
                        Button(L("Ayarı aç")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                if prefs.isOn(.xdr) {
                    if boost.available {
                        HStack {
                            Text(L("Ekstra parlaklık"))
                            Slider(value: Binding(get: { boost.factor }, set: { v in
                                if v > 1.001 { _ = Brightness.set(1) }
                                boost.set(v)
                            }), in: 1...boost.maxFactor)
                            Text("%\(Int((boost.factor * 100).rounded()))").monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                    } else {
                        Text(L("Bu ekran HDR ek parlaklığını desteklemiyor.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("Ses ve parlaklık tuşları"))
            } footer: {
                Text(L("İzin verildiğinde ses ve parlaklık tuşlarında macOS'in göstergesi yerine çentikteki gösterge çıkar; parlaklık %100'deyken artırmaya devam ederseniz HDR aralığına geçer. İzin yokken tuşlar her zamanki gibi çalışır."))
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in trusted = MediaKeyTap.shared.trusted }
            Section {
                Picker(L("Dil"), selection: Binding(get: { AppLanguage.selection }, set: { AppLanguage.set($0) })) {
                    Text(L("Sistem dili")).tag("system")
                    Text("Türkçe").tag("tr")
                    Text("English").tag("en")
                }
            } footer: {
                Text(L("Dili değiştirmek için Ada yeniden başlatılır."))
            }
            Section(L("Kısayol")) {
                Toggle(L("⌥ Boşluk ile asistanı aç"), isOn: $prefs.hotkey)
                Toggle(L("⌥⇧ Boşluk ile seçili metni asistana gönder"), isOn: $prefs.selectionHotkey)
            }
            Section(L("Başlangıç")) {
                Toggle(L("Oturum açıldığında Ada'yı başlat"), isOn: Binding(
                    get: { loginItem },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginItem = on
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Button(L("Ada'dan Çık")) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettings: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                ThemePicker()
                if prefs.theme != "black" && prefs.theme != "glass" {
                    ColorPicker(L("Tema rengi 1"), selection: Binding(get: { prefs.themeColor1 }, set: { prefs.color1 = $0.hexString }), supportsOpacity: false)
                    ColorPicker(L("Tema rengi 2"), selection: Binding(get: { prefs.themeColor2 }, set: { prefs.color2 = $0.hexString }), supportsOpacity: false)
                    HStack {
                        Text(L("Hazır renkler"))
                        Spacer()
                        ForEach(AppearanceSettings.palettes, id: \.0) { pal in
                            Button {
                                prefs.color1 = pal.1
                                prefs.color2 = pal.2
                            } label: {
                                LinearGradient(colors: [Color(hex: pal.1) ?? .gray, Color(hex: pal.2) ?? .gray], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 34, height: 18)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(pal.0)
                        }
                    }
                }
                if prefs.theme != "black" && prefs.theme != "neon" {
                    HStack {
                        Text(L("Cam saydamlığı"))
                        Slider(value: $prefs.glassClarity, in: 0...1)
                        Text("%\(Int((prefs.glassClarity * 100).rounded()))").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                Picker(L("Vurgu rengi"), selection: $prefs.accent) {
                    ForEach(Prefs.accents, id: \.id) { a in
                        Label { Text(a.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(a.color) }.tag(a.id)
                    }
                }
            } header: {
                Text(L("Tema"))
            } footer: {
                Text(L("Saydamlık arttıkça arkadaki içerik daha net görünür; parlak arka planlarda yazıların okunması zorlaşabilir."))
            }

            Section {
                HStack {
                    Text(L("Siyahın aşağı uzanması"))
                    Slider(value: $prefs.notchBlend, in: 0...1)
                    Text("%\(Int((prefs.notchBlend * 100).rounded()))").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Toggle(L("Kapalı çentikte kenarı yumuşat"), isOn: $prefs.wingFeather)
            } header: {
                Text(L("Çentikle birleşme"))
            } footer: {
                Text(L("Ada'nın çizdiği siyah tam siyahtır; yine de ekranın arka ışığı yüzünden fiziksel çentikten biraz daha açık görünebilir. Bu fark parlaklık yükseldikçe ve ekstra (HDR) parlaklık açıkken artar."))
            }

            Section(L("Boyut")) {
                slider(L("Genişlik"), $prefs.expandedWidth, 560...880, unit: "pt")
                slider(L("Yükseklik"), $prefs.expandedHeight, 200...400, unit: "pt")
                slider(L("Köşe yuvarlaklığı"), $prefs.cornerRadius, 8...48, unit: "pt")
                Button(L("Varsayılan boyuta dön")) {
                    prefs.expandedWidth = 720
                    prefs.expandedHeight = 240
                    prefs.cornerRadius = 30
                }
            }

            Section {
                percent(L("Renk sıcaklığı"), $prefs.warmth, 0...1)
                HStack {
                    Text(L("Kontrast"))
                    Slider(value: $prefs.contrast, in: -0.3...0.4)
                    Text(String(format: "%+d", Int((prefs.contrast * 100).rounded()))).monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                percent(L("Ek karartma"), $prefs.dim, 0...0.7)
                Button(L("Ekranı varsayılana döndür")) {
                    prefs.warmth = 0
                    prefs.contrast = 0
                    prefs.dim = 0
                }
            } header: {
                Text(L("Ekran iyileştirme"))
            } footer: {
                Text(L("Ekranın renk tablosunu değiştirir: sıcaklık gece için maviyi azaltır, ek karartma en düşük parlaklığın da altına iner. Ada kapanınca ekran normale döner. Ekran görüntülerine yansımaz."))
            }

            TabOrderSection()

            Section(L("Kapalı çentik")) {
                Toggle(L("Müzik çalarken kapak ve ekolayzır göster"), isOn: $prefs.showMusicWings)
                Toggle(L("Bir saat içindeki toplantıyı geri sayımla göster"), isOn: $prefs.showMeeting)
            }

        }
        .formStyle(.grouped)
    }

    private func percent(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text("%\(Int((value.wrappedValue * 100).rounded()))").monospacedDigit().frame(width: 64, alignment: .trailing)
        }
    }

    static let palettes: [(String, String, String)] = [
        (L("Mor gece"), "#7B5CFF", "#00D4FF"), (L("Gün batımı"), "#FF5E62", "#FF9966"), (L("Orman"), "#00C9A7", "#C4FCEF"),
        (L("Şeker"), "#FF6CAB", "#7366FF"), (L("Lav"), "#FF3D00", "#FFD600"), (L("Buz"), "#74EBD5", "#ACB6E5"),
    ]

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue.rounded())) \(unit)").monospacedDigit().frame(width: 64, alignment: .trailing)
        }
    }
}
