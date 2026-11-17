import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ModulesSettings().tabItem { Label(L("Modüller"), systemImage: "square.grid.2x2") }
            AppearanceSettings().tabItem { Label(L("Görünüm"), systemImage: "paintbrush") }
            AssistantSettings().tabItem { Label(L("Asistan"), systemImage: "sparkles") }
            GeneralSettings().tabItem { Label(L("Genel"), systemImage: "gearshape") }
        }
        .padding(.top, 8)
        .frame(width: 620, height: 560)
    }
}

struct ModulesSettings: View {
    @ObservedObject var prefs = Prefs.shared

    private let groups: [(String, [ModuleID])] = [
        (L("Ana sekme"), [.music, .lyrics, .calendar, .reminders, .weather]),
        (L("Canlı bildirimler ve ekran"), [.battery, .bluetooth, .hud, .xdr]),
        (L("Araçlar"), [.timer, .clipboard, .notes, .stats, .shelf, .launcher, .mirror]),
        (L("Asistan"), [.assistant]),
    ]

    var body: some View {
        Form {
            ForEach(groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { m in
                        Toggle(isOn: prefs.binding(m)) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title)
                                    Text(m.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: m.icon).frame(width: 20)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
                Picker(L("Tema"), selection: $prefs.theme) {
                    ForEach(Prefs.themes, id: \.id) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
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

            Section(L("Kapalı çentik")) {
                Toggle(L("Müzik çalarken kapak ve ekolayzır göster"), isOn: $prefs.showMusicWings)
                Toggle(L("Bir saat içindeki toplantıyı geri sayımla göster"), isOn: $prefs.showMeeting)
            }

            Section {
                Button(L("Çentiği aç ve önizle")) { NotchController.shared.preview() }
            } footer: {
                Text(L("Önizleme 6 saniye açık kalır; ayarları değiştirdikçe anında güncellenir."))
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
