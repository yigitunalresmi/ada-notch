import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ModulesSettings().tabItem { Label("Modüller", systemImage: "square.grid.2x2") }
            AppearanceSettings().tabItem { Label("Görünüm", systemImage: "paintbrush") }
            AssistantSettings().tabItem { Label("Asistan", systemImage: "sparkles") }
            GeneralSettings().tabItem { Label("Genel", systemImage: "gearshape") }
        }
        .padding(.top, 8)
        .frame(width: 620, height: 560)
    }
}

struct ModulesSettings: View {
    @ObservedObject var prefs = Prefs.shared

    private let groups: [(String, [ModuleID])] = [
        ("Ana sekme", [.music, .lyrics, .calendar, .reminders, .weather]),
        ("Canlı bildirimler ve ekran", [.battery, .bluetooth, .hud, .xdr]),
        ("Araçlar", [.timer, .clipboard, .notes, .stats, .shelf, .launcher, .mirror]),
        ("Asistan", [.assistant]),
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
                    Button("Kaydet") {
                        Keychain.set(key)
                        key = ""
                        saved = (Keychain.get() ?? "").isEmpty == false
                        AssistantEngine.shared.refreshKey()
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Label(saved ? "Anahtar kayıtlı (Anahtar Zinciri'nde saklanıyor)" : "Henüz anahtar yok",
                          systemImage: saved ? "checkmark.seal.fill" : "key")
                        .foregroundStyle(saved ? .green : .secondary)
                        .font(.callout)
                    Spacer()
                    if saved {
                        Button("Sil", role: .destructive) {
                            Keychain.set("")
                            saved = false
                            AssistantEngine.shared.refreshKey()
                        }
                    }
                }
            } header: {
                Text("Anthropic API anahtarı")
            } footer: {
                Text("Anahtarı console.anthropic.com adresinden alabilirsiniz. Yalnızca bu Mac'in Anahtar Zinciri'nde saklanır ve yalnızca api.anthropic.com'a gönderilir.")
            }

            Section("Model ve ses") {
                Picker("Model", selection: $prefs.model) {
                    ForEach(ClaudeClient.models, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("Konuşma dili", selection: $prefs.speechLocale) {
                    Text("Türkçe").tag("tr-TR")
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Deutsch").tag("de-DE")
                }
                Toggle("Yanıtları sesli oku", isOn: $prefs.speakReplies)
                Picker("Yanıt biçimi", selection: $prefs.effort) {
                    Text("Hızlı").tag("low")
                    Text("Dengeli").tag("medium")
                    Text("Derinlemesine (yavaş, pahalı)").tag("high")
                }
            }

            Section {
                TextEditor(text: $prefs.customInstructions)
                    .font(.body)
                    .frame(height: 70)
            } header: {
                Text("Özel talimatlar")
            } footer: {
                Text("Asistanın her sohbette uymasını istediğiniz kurallar. Örnek: \"Bana sen diye hitap et, yanıtları tek cümle tut.\"")
            }

            Section {
                if prefs.memory.isEmpty {
                    Text("Henüz kayıtlı bir şey yok. Asistana \"şunu hatırla…\" diyebilirsiniz.")
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
                Text("Hafıza")
            } footer: {
                Text("Asistanın sizin hakkınızda hatırladıkları. Yalnızca bu Mac'te saklanır ve her sohbette Claude'a gönderilir.")
            }

            Section {
                Toggle(isOn: $prefs.allowWeb) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Web araması")
                        Text("Asistan güncel bilgi için internette arama yapabilir (Anthropic tarafında çalışır, ek ücretlidir).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $prefs.allowScreen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ekrana bakabilsin")
                        Text("İstediğinizde ekran görüntüsü alıp Claude'a gönderir. macOS ekran kaydı izni ister.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $prefs.allowAppleScript) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AppleScript çalıştırabilsin")
                        Text("Diğer araçların yapamadığı işler için. Her betik çalışmadan önce size gösterilir ve onayınız istenir.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Asistanın yetkileri")
            } footer: {
                Text("Takvim, anımsatıcı, müzik, ses, parlaklık, görünüm, uygulama açma/kapama, zamanlayıcı, pano, not ve Ada modülleri her zaman kullanılabilir.")
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
            Section("Çentik") {
                Toggle("Fareyle üzerine gelince aç", isOn: $prefs.openOnHover)
                if prefs.openOnHover {
                    HStack {
                        Text("Açılma gecikmesi")
                        Slider(value: $prefs.hoverDelay, in: 0...0.8)
                        Text(String(format: "%.2f sn", prefs.hoverDelay)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                } else {
                    Text("Kapalıyken çentiğe tıklayarak açılır.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Kapanma gecikmesi")
                    Slider(value: $prefs.closeDelay, in: 0.1...2)
                    Text(String(format: "%.1f sn", prefs.closeDelay)).monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                Toggle("Son açık sekmeyi hatırla", isOn: $prefs.rememberTab)
                Toggle("Açılırken dokunsal geri bildirim", isOn: $prefs.haptics)
            }
            Section("Modül ayarları") {
                Picker("Sıcaklık birimi", selection: $prefs.fahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                HStack {
                    Text("Pano geçmişi")
                    Slider(value: $prefs.clipboardLimit, in: 10...100, step: 10)
                    Text("\(Int(prefs.clipboardLimit)) öğe").monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                Toggle("Zamanlayıcı bitince ses çal", isOn: $prefs.timerSound)
                Stepper("Pomodoro odak süresi: \(Int(prefs.pomodoroWork)) dk", value: $prefs.pomodoroWork, in: 5...90, step: 5)
                Stepper("Pomodoro mola süresi: \(Int(prefs.pomodoroBreak)) dk", value: $prefs.pomodoroBreak, in: 1...30, step: 1)
                HStack {
                    Text("HDR üst sınırı")
                    Slider(value: $prefs.hdrMax, in: 1.2...1.6, step: 0.1)
                    Text("%\(Int((prefs.hdrMax * 100).rounded()))").monospacedDigit().frame(width: 64, alignment: .trailing)
                }
            }
            Section {
                HStack {
                    Label(trusted ? "Erişilebilirlik izni verildi" : "Erişilebilirlik izni yok",
                          systemImage: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Spacer()
                    if !trusted {
                        Button("İzin iste") { MediaKeyTap.shared.requestTrust() }
                        Button("Ayarı aç") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                if prefs.isOn(.xdr) {
                    if boost.available {
                        HStack {
                            Text("Ekstra parlaklık")
                            Slider(value: Binding(get: { boost.factor }, set: { v in
                                if v > 1.001 { _ = Brightness.set(1) }
                                boost.set(v)
                            }), in: 1...boost.maxFactor)
                            Text("%\(Int((boost.factor * 100).rounded()))").monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                    } else {
                        Text("Bu ekran HDR ek parlaklığını desteklemiyor.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Ses ve parlaklık tuşları")
            } footer: {
                Text("İzin verildiğinde ses ve parlaklık tuşlarında macOS'in göstergesi yerine çentikteki gösterge çıkar; parlaklık %100'deyken artırmaya devam ederseniz HDR aralığına geçer. İzin yokken tuşlar her zamanki gibi çalışır.")
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in trusted = MediaKeyTap.shared.trusted }
            Section("Kısayol") {
                Toggle("⌥ Boşluk ile asistanı aç", isOn: $prefs.hotkey)
            }
            Section("Başlangıç") {
                Toggle("Oturum açıldığında Ada'yı başlat", isOn: Binding(
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
                Button("Ada'dan Çık") { NSApp.terminate(nil) }
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
                Toggle("Cam (Liquid Glass) görünüm", isOn: $prefs.glass)
                if prefs.glass {
                    HStack {
                        Text("Cam saydamlığı")
                        Slider(value: $prefs.glassClarity, in: 0...1)
                        Text("%\(Int((prefs.glassClarity * 100).rounded()))").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                Picker("Vurgu rengi", selection: $prefs.accent) {
                    ForEach(Prefs.accents, id: \.id) { a in
                        Label { Text(a.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(a.color) }.tag(a.id)
                    }
                }
            } header: {
                Text("Cam ve renk")
            } footer: {
                Text("Saydamlık arttıkça arkadaki içerik daha net görünür; parlak arka planlarda yazıların okunması zorlaşabilir.")
            }

            Section("Boyut") {
                slider("Genişlik", $prefs.expandedWidth, 560...880, unit: "pt")
                slider("Yükseklik", $prefs.expandedHeight, 200...400, unit: "pt")
                slider("Köşe yuvarlaklığı", $prefs.cornerRadius, 8...48, unit: "pt")
                Button("Varsayılan boyuta dön") {
                    prefs.expandedWidth = 720
                    prefs.expandedHeight = 240
                    prefs.cornerRadius = 30
                }
            }

            Section("Kapalı çentik") {
                Toggle("Müzik çalarken kapak ve ekolayzır göster", isOn: $prefs.showMusicWings)
                Toggle("Bir saat içindeki toplantıyı geri sayımla göster", isOn: $prefs.showMeeting)
            }

            Section {
                Button("Çentiği aç ve önizle") { NotchController.shared.preview() }
            } footer: {
                Text("Önizleme 6 saniye açık kalır; ayarları değiştirdikçe anında güncellenir.")
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue.rounded())) \(unit)").monospacedDigit().frame(width: 64, alignment: .trailing)
        }
    }
}
