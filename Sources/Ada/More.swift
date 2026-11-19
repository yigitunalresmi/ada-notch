import AppKit
import CoreAudio
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Asistana dosya ve görsel ekleme

enum Attachment {
    static let maxCount = 5

    /// Dosyayı Claude'a gönderilecek içerik bloğuna çevirir; desteklenmiyorsa nil.
    static func block(for url: URL) -> [String: Any]? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return textBlock(url) }
        if type.conforms(to: .image) {
            guard let image = NSImage(contentsOf: url), let b64 = ToolBox.jpegBase64(image, maxWidth: 1568) else { return nil }
            return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]]
        }
        if type.conforms(to: .pdf) {
            guard let data = try? Data(contentsOf: url), data.count <= 20 * 1024 * 1024 else { return nil }
            return ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()]]
        }
        return textBlock(url)
    }

    private static func textBlock(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), data.count <= 400_000,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return ["type": "text", "text": "<file name=\"\(url.lastPathComponent)\">\n\(text)\n</file>"]
    }
}

struct AttachmentChips: View {
    @ObservedObject var engine = AssistantEngine.shared

    var body: some View {
        if !engine.attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(engine.attachments, id: \.self) { url in
                        HStack(spacing: 5) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 15, height: 15)
                            Text(url.lastPathComponent).font(.system(size: 10.5)).lineLimit(1).frame(maxWidth: 150)
                            Button { engine.attachments.removeAll { $0 == url } } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .glassCard(Capsule())
                    }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Sohbet geçmişi

struct SavedChat: Codable, Identifiable, Equatable {
    struct Item: Codable, Equatable {
        var role: String
        var text: String
    }

    var id: UUID
    var date: Date
    var title: String
    var items: [Item]
}

final class ChatStore: ObservableObject {
    static let shared = ChatStore()
    @Published private(set) var chats: [SavedChat] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ada", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chats.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([SavedChat].self, from: data) {
            chats = list
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(chats) { try? data.write(to: url, options: .atomic) }
    }

    func save(id: UUID, items: [ChatItem]) {
        let kept = items.compactMap { item -> SavedChat.Item? in
            switch item.role {
            case .user: return .init(role: "user", text: item.text)
            case .assistant: return .init(role: "assistant", text: item.text)
            default: return nil
            }
        }
        guard let first = kept.first(where: { $0.role == "user" }) else { return }
        let chat = SavedChat(id: id, date: Date(), title: String(first.text.prefix(70)), items: kept)
        chats.removeAll { $0.id == id }
        chats.insert(chat, at: 0)
        if chats.count > 60 { chats.removeLast(chats.count - 60) }
        persist()
    }

    func delete(_ id: UUID) {
        chats.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        chats = []
        persist()
    }
}

struct ChatHistoryView: View {
    @ObservedObject var store = ChatStore.shared
    @Binding var visible: Bool
    @State private var query = ""

    var body: some View {
        let list = store.chats.filter { chat in
            query.isEmpty || chat.title.localizedCaseInsensitiveContains(query) || chat.items.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SectionTitle(text: L("Sohbet geçmişi"))
                TextField(L("Ara"), text: $query)
                    .textFieldStyle(.plain).font(.system(size: 11.5))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .glassCard(Capsule())
                    .onTapGesture { NotchController.shared.makeKey() }
                Button(L("Kapat")) { visible = false }.buttonStyle(PillButtonStyle())
            }
            if list.isEmpty {
                EmptyHint(icon: "clock.arrow.circlepath", text: store.chats.isEmpty ? L("Henüz kayıtlı sohbet yok.") : L("Eşleşen sohbet yok."))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(list) { chat in
                            HStack(spacing: 8) {
                                Button {
                                    AssistantEngine.shared.load(chat)
                                    visible = false
                                } label: {
                                    HStack {
                                        Text(chat.title).font(.system(size: 11.5)).lineLimit(1)
                                        Spacer(minLength: 6)
                                        Text(Self.when(chat.date)).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button { store.delete(chat.id) } label: {
                                    Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                                }
                                .buttonStyle(HoverIconStyle())
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .glassCard(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private static func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = appLocale
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "d MMM"
        return f.string(from: d)
    }
}

// MARK: - Kendi komutlarınız ("/çevir …")

struct SlashCommand: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var prompt: String
}

final class CommandStore: ObservableObject {
    static let shared = CommandStore()
    @Published var commands: [SlashCommand] { didSet { save() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "commands"), let list = try? JSONDecoder().decode([SlashCommand].self, from: data) {
            commands = list
        } else {
            commands = appLanguage == "tr" ? [
                SlashCommand(name: "çevir", prompt: "Şu metni İngilizceye çevir, yalnızca çeviriyi ver: {metin}"),
                SlashCommand(name: "özetle", prompt: "Şu metni üç maddede özetle: {metin}"),
                SlashCommand(name: "eposta", prompt: "Şu notlardan kısa ve kibar bir e-posta yaz: {metin}"),
            ] : [
                SlashCommand(name: "translate", prompt: "Translate this text to Turkish and return only the translation: {metin}"),
                SlashCommand(name: "summarise", prompt: "Summarise this text in three bullet points: {metin}"),
                SlashCommand(name: "email", prompt: "Write a short, polite email from these notes: {metin}"),
            ]
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(commands) { UserDefaults.standard.set(data, forKey: "commands") }
    }

    /// "/ad geri kalan" biçimindeki girişi komutun talimatına çevirir; komut değilse metni aynen döndürür.
    func expand(_ input: String) -> String {
        guard input.hasPrefix("/") else { return input }
        let body = input.dropFirst()
        let name = body.prefix { !$0.isWhitespace }.lowercased()
        guard let cmd = commands.first(where: { $0.name.lowercased() == name }) else { return input }
        var rest = body.dropFirst(name.count).trimmingCharacters(in: .whitespacesAndNewlines)
        // Metin verilmediyse seçili metni, o da yoksa panoyu kullan.
        if rest.isEmpty { rest = AssistantEngine.shared.selection ?? NSPasteboard.general.string(forType: .string) ?? "" }
        if cmd.prompt.contains("{metin}") { return cmd.prompt.replacingOccurrences(of: "{metin}", with: rest) }
        return rest.isEmpty ? cmd.prompt : cmd.prompt + "\n\n" + rest
    }

    func matches(_ draft: String) -> [SlashCommand] {
        guard draft.hasPrefix("/"), !draft.contains(" ") else { return [] }
        let q = draft.dropFirst().lowercased()
        return commands.filter { q.isEmpty || $0.name.lowercased().hasPrefix(q) }
    }
}

// MARK: - Zamanlanmış görevler

struct ScheduledTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var prompt: String
    var hour = 9
    var minute = 0
    /// 0: her gün belirtilen saatte. Aksi halde bu kadar saatte bir.
    var everyHours = 0
    var enabled = true
    var lastRun: Date?
}

final class Scheduler: ObservableObject {
    static let shared = Scheduler()
    @Published var tasks: [ScheduledTask] { didSet { save() } }
    private var timer: Timer?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "scheduledTasks"), let list = try? JSONDecoder().decode([ScheduledTask].self, from: data) {
            tasks = list
        } else {
            tasks = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) { UserDefaults.standard.set(data, forKey: "scheduledTasks") }
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func isDue(_ task: ScheduledTask, now: Date) -> Bool {
        guard task.enabled else { return false }
        if task.everyHours > 0 {
            guard let last = task.lastRun else { return true }
            return now.timeIntervalSince(last) >= Double(task.everyHours) * 3600
        }
        guard let planned = Calendar.current.date(bySettingHour: task.hour, minute: task.minute, second: 0, of: now) else { return false }
        // Mac o saatte kapalıysa üç saat içinde açıldığında yine çalışır.
        guard now >= planned, now.timeIntervalSince(planned) < 3 * 3600 else { return false }
        if let last = task.lastRun, last >= planned { return false }
        return true
    }

    private func tick() {
        guard Prefs.shared.isOn(.assistant), AssistantEngine.shared.hasKey, !AssistantEngine.shared.busy else { return }
        let now = Date()
        guard let index = tasks.firstIndex(where: { isDue($0, now: now) }) else { return }
        tasks[index].lastRun = now
        let task = tasks[index]
        Task { @MainActor in
            AssistantEngine.shared.runScheduled(title: task.title, prompt: task.prompt)
        }
    }

    func runNow(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }), !AssistantEngine.shared.busy else { return }
        Task { @MainActor in AssistantEngine.shared.runScheduled(title: task.title, prompt: task.prompt) }
    }
}

struct ScheduledTasksSection: View {
    @ObservedObject var scheduler = Scheduler.shared

    var body: some View {
        Section {
            if scheduler.tasks.isEmpty {
                Text(L("Henüz görev yok. Aşağıdan hazır bir görev ekleyebilirsiniz.")).font(.callout).foregroundStyle(.secondary)
            }
            ForEach($scheduler.tasks) { $task in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("", isOn: $task.enabled).labelsHidden()
                        TextField(L("Başlık"), text: $task.title).textFieldStyle(.roundedBorder)
                        Button { scheduler.runNow(task.id) } label: { Image(systemName: "play.fill") }
                            .buttonStyle(.borderless).help(L("Şimdi çalıştır"))
                        Button { scheduler.tasks.removeAll { $0.id == task.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    HStack {
                        Picker("", selection: Binding(get: { task.everyHours > 0 }, set: { task.everyHours = $0 ? 3 : 0 })) {
                            Text(L("Her gün saat")).tag(false)
                            Text(L("Aralıklarla")).tag(true)
                        }
                        .labelsHidden().frame(width: 140)
                        if task.everyHours > 0 {
                            Stepper(Lf("%@ saatte bir", "\(task.everyHours)"), value: $task.everyHours, in: 1...48)
                        } else {
                            DatePicker("", selection: Binding(
                                get: { Calendar.current.date(bySettingHour: task.hour, minute: task.minute, second: 0, of: Date()) ?? Date() },
                                set: { d in
                                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                    task.hour = c.hour ?? 9
                                    task.minute = c.minute ?? 0
                                }), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        Spacer()
                    }
                    TextField(L("Asistana verilecek talimat"), text: $task.prompt, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 2)
            }
            HStack {
                Button(L("Sabah özeti ekle")) {
                    scheduler.tasks.append(ScheduledTask(title: L("Sabah özeti"),
                        prompt: L("Bugünkü takvimimi, hava durumunu ve bekleyen anımsatıcılarımı üç dört cümleyle özetle."), hour: 9, minute: 0))
                }
                Button(L("Takip ekle")) {
                    scheduler.tasks.append(ScheduledTask(title: L("Takip"),
                        prompt: L("Şunun güncel durumunu web'de ara ve tek cümleyle söyle: (kargo takip numarası ya da uçuş kodu yazın)"), everyHours: 3, lastRun: Date()))
                }
                Button(L("Boş görev ekle")) {
                    scheduler.tasks.append(ScheduledTask(title: L("Yeni görev"), prompt: ""))
                }
            }
        } header: {
            Text(L("Zamanlanmış görevler"))
        } footer: {
            Text(L("Görev saati geldiğinde asistan talimatı kendisi çalıştırır ve sonucu çentikte gösterir. Her çalıştırma API kullanır. Mac o saatte kapalıysa üç saat içinde açıldığında çalışır."))
        }
    }
}

struct CommandsSection: View {
    @ObservedObject var store = CommandStore.shared

    var body: some View {
        Section {
            ForEach($store.commands) { $cmd in
                HStack(alignment: .top) {
                    HStack(spacing: 1) {
                        Text("/").foregroundStyle(.secondary)
                        TextField(L("ad"), text: $cmd.name).textFieldStyle(.roundedBorder).frame(width: 90)
                    }
                    TextField(L("Talimat"), text: $cmd.prompt, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
                    Button { store.commands.removeAll { $0.id == cmd.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
            Button(L("Komut ekle")) { store.commands.append(SlashCommand(name: "", prompt: "{metin}")) }
        } header: {
            Text(L("Komutlar"))
        } footer: {
            Text(L("Asistan kutusuna \"/ad metin\" yazınca talimat çalışır; {metin} yerine yazdığınız metin gelir. Metin yazmazsanız seçili metin ya da pano kullanılır."))
        }
    }
}

// MARK: - Mikrofon kontrolü

enum Microphone {
    private static var savedVolume: Float32 = 0.75

    private static func device() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                             mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    private static var volumeAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                               mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)

    private static func volume() -> Float32? {
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = volumeAddr
        return AudioObjectGetPropertyData(device(), &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    static var muted: Bool {
        var m = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = muteAddr
        if AudioObjectGetPropertyData(device(), &addr, 0, nil, &size, &m) == noErr, m != 0 { return true }
        if let v = volume() { return v < 0.01 }
        return false
    }

    /// Sistem düzeyinde mikrofonu kapatır/açar; hangi toplantı uygulaması olursa olsun çalışır.
    static func setMuted(_ on: Bool) {
        var m = UInt32(on ? 1 : 0)
        var addr = muteAddr
        if AudioObjectSetPropertyData(device(), &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m) == noErr { return }
        // Sessize alma desteklenmiyorsa giriş düzeyini sıfırla.
        if on, let v = volume(), v > 0.01 { savedVolume = v }
        var v: Float32 = on ? 0 : savedVolume
        var vaddr = volumeAddr
        AudioObjectSetPropertyData(device(), &vaddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    static func toggle() {
        let on = !muted
        setMuted(on)
        MicState.shared.muted = on
        NotchModel.shared.showHUD(HUDInfo(icon: on ? "mic.slash.fill" : "mic.fill",
                                          title: on ? L("Mikrofon kapalı") : L("Mikrofon açık"), tint: on ? .red : .green), seconds: 1.8)
    }
}

final class MicState: ObservableObject {
    static let shared = MicState()
    @Published var muted = Microphone.muted
}

// MARK: - Odak istatistikleri

final class FocusStats: ObservableObject {
    static let shared = FocusStats()
    /// "yyyy-MM-dd" → odak dakikası
    @Published private(set) var log: [String: Double]

    private init() { log = (UserDefaults.standard.dictionary(forKey: "focusLog") as? [String: Double]) ?? [:] }

    private static func key(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    func add(minutes: Double) {
        guard minutes >= 1 else { return }
        log[Self.key(Date()), default: 0] += minutes
        // Altı aydan eski kayıtları at.
        if log.count > 190 {
            let cutoff = Self.key(Date().addingTimeInterval(-180 * 86400))
            log = log.filter { $0.key >= cutoff }
        }
        UserDefaults.standard.set(log, forKey: "focusLog")
    }

    var today: Double { log[Self.key(Date())] ?? 0 }

    /// Son yedi gün, en eskiden bugüne.
    var week: [Double] {
        (0..<7).reversed().map { log[Self.key(Date().addingTimeInterval(-Double($0) * 86400))] ?? 0 }
    }

    static func text(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? Lf("%@ sa %@ dk", "\(m / 60)", "\(m % 60)") : Lf("%@ dk", "\(m)")
    }
}

struct FocusStatsView: View {
    @ObservedObject var stats = FocusStats.shared

    var body: some View {
        let week = stats.week
        let top = max(30, week.max() ?? 30)
        HStack(alignment: .bottom, spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(week.enumerated()), id: \.offset) { index, value in
                    Capsule()
                        .fill(index == 6 ? Color.orange : Color.white.opacity(0.3))
                        .frame(width: 4, height: max(2, 16 * CGFloat(value / top)))
                }
            }
            .frame(height: 16, alignment: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Bugün odak")).font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.45))
                Text(FocusStats.text(stats.today)).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            }
        }
        .help(Lf("Son 7 gün: %@", FocusStats.text(week.reduce(0, +))))
    }
}

// MARK: - Mail araçları

enum MailBridge {
    static var running: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.mail" }
    }

    static func selectedMessage() async -> ToolOutput {
        guard running else { return .fail("Mail is not running. Open Mail and select a message first.") }
        let src = """
        tell application id "com.apple.mail"
            set sel to selection
            if (count of sel) is 0 then return "NONE"
            set m to item 1 of sel
            return (subject of m) & "|~|" & (sender of m) & "|~|" & (content of m)
        end tell
        """
        let r = await Script.run(src)
        if let err = r.err { return .fail("Could not read Mail: \(err). The user may need to allow Ada to control Mail in System Settings › Privacy & Security › Automation.") }
        guard let out = r.out, out != "NONE" else { return .fail("No message is selected in Mail.") }
        let parts = out.components(separatedBy: "|~|")
        guard parts.count >= 3 else { return .fail("Could not parse the selected message.") }
        return .ok("Subject: \(parts[0])\nFrom: \(parts[1])\n\n\(String(parts[2].prefix(20000)))")
    }

    /// Bir taslak penceresi açar; asla göndermez.
    static func draft(to: String?, subject: String?, body: String, replyToSelected: Bool) async -> ToolOutput {
        let b = body.appleScriptQuoted
        let src: String
        if replyToSelected {
            guard running else { return .fail("Mail is not running.") }
            src = """
            tell application id "com.apple.mail"
                set sel to selection
                if (count of sel) is 0 then return "NONE"
                set r to reply (item 1 of sel) with opening window
                set content of r to \(b) & return & return & (content of r as string)
                activate
                return "OK"
            end tell
            """
        } else {
            let recipient = (to ?? "").isEmpty ? "" : "make new to recipient at end of to recipients of r with properties {address:\((to ?? "").appleScriptQuoted)}"
            src = """
            tell application id "com.apple.mail"
                set r to make new outgoing message with properties {subject:\((subject ?? "").appleScriptQuoted), content:\(b), visible:true}
                tell r
                    \(recipient)
                end tell
                activate
                return "OK"
            end tell
            """
        }
        let r = await Script.run(src)
        if let err = r.err { return .fail("Could not create the draft: \(err)") }
        if r.out == "NONE" { return .fail("No message is selected in Mail to reply to.") }
        return .ok("A draft window is open in Mail. It has not been sent; the user must review and send it.")
    }
}

// MARK: - Görünüm ayarları: sekme sırası ve ekran

struct TabOrderSection: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Section {
            let order = prefs.orderedTabs
            ForEach(Array(order.enumerated()), id: \.element) { index, tab in
                HStack {
                    Image(systemName: tab.icon).frame(width: 22)
                    Text(tab.title)
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(index == 0)
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).disabled(index == order.count - 1)
                }
            }
        } header: {
            Text(L("Sekme sırası"))
        } footer: {
            Text(L("Bir sekmeyi gizlemek için Modüller sayfasından ilgili modülü kapatın."))
        }
    }

    private func move(_ index: Int, by delta: Int) {
        var order = prefs.orderedTabs
        let target = index + delta
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        prefs.tabOrder = order.map(\.rawValue)
    }
}

struct ScreenPicker: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Picker(L("Ada'nın duracağı ekran"), selection: $prefs.screenName) {
            Text(L("Otomatik (çentikli ekran)")).tag("")
            ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }
}
