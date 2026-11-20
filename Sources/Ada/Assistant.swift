import AVFoundation
import AppKit
import Foundation
import Security
import Speech

// MARK: - Anahtar zinciri

enum Keychain {
    private static let service = "app.ada.notch"
    private static let account = "anthropic-api-key"

    /// Anahtar başka bir imzayla (ör. eski bir sürümle) kaydedildiyse macOS her okumada parola sorar.
    /// Bir kez yeniden kaydedince öğe bu sürümün olur ve soru biter.
    static func adoptIfNeeded() {
        let flag = "keychainOwner", me = "developer-id-1"
        guard UserDefaults.standard.string(forKey: flag) != me else { return }
        if let value = get(), !value.isEmpty { set(value) }
        UserDefaults.standard.set(me, forKey: flag)
    }

    static func get() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(v.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Claude API (Swift için resmî SDK olmadığından doğrudan HTTP)

struct ClaudeError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }
}

enum ClaudeClient {
    static let models: [(id: String, name: String)] = [
        ("claude-opus-5-5", L("Claude Opus 5.5 (önerilen)")),
        ("claude-sonnet-5-5", L("Claude Sonnet 5.5 (daha hızlı, daha ucuz)")),
        ("claude-haiku-5-5", L("Claude Haiku 5.5 (en hızlı)")),
    ]

    static func send(messages: [[String: Any]], system: String, tools: [[String: Any]]) async throws -> [String: Any] {
        guard let key = Keychain.get(), !key.isEmpty else {
            throw ClaudeError(status: 0, message: L("API anahtarı girilmemiş. Ayarlar › Asistan bölümünden ekleyin."))
        }
        let model = Prefs.shared.model
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": messages,
            "tools": tools,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": Prefs.shared.effort],
            "cache_control": ["type": "ephemeral"],
        ]
        // Güvenlik sınıflandırıcısı bir isteği reddederse sunucu başka bir modele düşer.
        let useFallback = model == "claude-opus-5-5" || model == "claude-sonnet-5-5"
        if useFallback { body["fallbacks"] = "default" }
        do {
            return try await post(body, key: key, beta: useFallback ? "server-side-fallback-2026-07-01" : nil)
        } catch let e as ClaudeError where useFallback && e.status == 400 && e.message.lowercased().contains("fallback") {
            body.removeValue(forKey: "fallbacks")
            return try await post(body, key: key, beta: nil)
        }
    }

    private static func post(_ body: [String: Any], key: String, beta: String?) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let beta { req.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        var lastError: Error = ClaudeError(status: 0, message: L("Bağlantı kurulamadı."))
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000) }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                if status == 200 { return json }
                let detail = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
                let err: ClaudeError
                switch status {
                case 401: err = ClaudeError(status: status, message: L("API anahtarı geçersiz. Ayarlar › Asistan bölümünden kontrol edin."))
                case 403: err = ClaudeError(status: status, message: Lf("Bu anahtarın bu modele erişim izni yok: %@", "\(detail)"))
                case 429: err = ClaudeError(status: status, message: L("İstek sınırına ulaşıldı, biraz sonra tekrar deneyin."))
                case 500...599: err = ClaudeError(status: status, message: Lf("Claude şu an yoğun (%@). Biraz sonra tekrar deneyin.", "\(status)"))
                default: err = ClaudeError(status: status, message: detail)
                }
                lastError = err
                if status == 429 || status >= 500 { continue }
                throw err
            } catch let e as ClaudeError {
                if e.status == 429 || e.status >= 500 { continue }
                throw e
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = ClaudeError(status: 0, message: Lf("Ağ hatası: %@", "\(error.localizedDescription)"))
            }
        }
        throw lastError
    }
}

// MARK: - Sohbet motoru

struct ChatItem: Identifiable, Equatable {
    enum Role { case user, assistant, tool, error }
    let id = UUID()
    var role: Role
    var text: String
}

struct PendingConfirm: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var continuation: CheckedContinuation<Bool, Never>
}

struct ToolOutput {
    var content: Any
    var isError = false
    static func ok(_ s: String) -> ToolOutput { ToolOutput(content: s) }
    static func fail(_ s: String) -> ToolOutput { ToolOutput(content: s, isError: true) }
}

final class AssistantEngine: ObservableObject {
    static let shared = AssistantEngine()

    @Published var items: [ChatItem] = []
    @Published var busy = false
    @Published var status = ""
    @Published var pending: PendingConfirm?
    /// Kısayolla alınan seçili metin; hızlı işlem kartında gösterilir.
    @Published var selection: String?
    /// Yazı efekti tamamlanmış yanıtlar.
    var revealed = Set<UUID>()
    @Published var hasKey = (Keychain.get() ?? "").isEmpty == false

    /// Bir sonraki mesaja eklenecek dosyalar.
    @Published var attachments: [URL] = []
    private var history: [[String: Any]] = []
    private var task: Task<Void, Never>?
    private var chatID = UUID()
    /// Zamanlanmış bir görev bittiğinde sonucu bildirmek için.
    private var scheduledTitle: String?

    func attach(_ urls: [URL]) {
        for url in urls where url.isFileURL && !attachments.contains(url) && attachments.count < Attachment.maxCount {
            attachments.append(url)
        }
    }

    func attach(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self.attach([url]) }
            }
        }
    }

    /// Kayıtlı bir sohbeti geri yükler. Bağlam yalnızca görünen metinlerden yeniden kurulur.
    @MainActor
    func load(_ chat: SavedChat) {
        stop()
        chatID = chat.id
        items = chat.items.map { ChatItem(role: $0.role == "user" ? .user : .assistant, text: $0.text) }
        revealed = Set(items.map(\.id))
        history = []
        for item in chat.items {
            if let last = history.last, last["role"] as? String == item.role, let text = last["content"] as? String {
                history[history.count - 1]["content"] = text + "\n\n" + item.text
            } else if !(history.isEmpty && item.role != "user") {
                history.append(["role": item.role, "content": item.text])
            }
        }
        attachments = []
    }

    /// Zamanlanmış görev: talimatı çalıştırır, bitince sonucu çentikte gösterir.
    @MainActor
    func runScheduled(title: String, prompt: String) {
        guard !busy, !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        scheduledTitle = title
        send(prompt, display: "⏰ " + title)
    }

    static let systemPrompt = """
    You are Ada, an assistant that lives in the notch of the user's MacBook. The user talks to you from a small panel at the top of the screen, sometimes by voice.

    Reply in the language the user writes in (usually Turkish). The panel is small, so keep replies short: one to four sentences unless the user asks for more. Plain text reads best there; avoid headings and tables.

    You can act on this Mac through your tools: calendar, reminders, music, volume, brightness, appearance, apps, timers, clipboard, the quick note, Ada's own feature toggles, and more. When the user asks for something a tool can do, do it rather than describing how. Report an action as done only after its tool result confirms it; if a tool fails, say what failed and what the user can do about it (often a macOS permission in System Settings › Privacy & Security).

    Each user message ends with a <context> block giving the current local date and time; use it to resolve words like "yarın" or "akşam 7". Ask before anything destructive or hard to undo, and when a request is ambiguous about which item it targets.
    """

    static func fullSystemPrompt() -> String {
        var s = systemPrompt
        let custom = Prefs.shared.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { s += "\n\nThe user's own standing instructions for you:\n" + custom }
        let memory = Prefs.shared.memory
        if !memory.isEmpty {
            s += "\n\nThings the user asked you to remember (saved with the remember tool):\n" + memory.map { "- " + $0 }.joined(separator: "\n")
        }
        return s
    }

    func refreshKey() { hasKey = (Keychain.get() ?? "").isEmpty == false }

    @MainActor
    func send(_ raw: String, display: String? = nil) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty || !attachments.isEmpty else { return }
        if text.isEmpty { text = L("Bunu incele ve kısaca anlat.") }
        // Ekleri içerik bloklarına çevir.
        var blocks: [[String: Any]] = []
        var names: [String] = []
        var skipped: [String] = []
        for url in attachments {
            if let block = Attachment.block(for: url) { blocks.append(block); names.append(url.lastPathComponent) } else { skipped.append(url.lastPathComponent) }
        }
        attachments = []
        let shown = (display ?? text) + (names.isEmpty ? "" : "\n📎 " + names.joined(separator: ", "))
        items.append(ChatItem(role: .user, text: shown))
        if !skipped.isEmpty {
            items.append(ChatItem(role: .error, text: Lf("Eklenemedi (desteklenmeyen tür ya da çok büyük): %@", skipped.joined(separator: ", "))))
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm EEEE"
        let ctx = "\n\n<context>now: \(f.string(from: Date())), timezone: \(TimeZone.current.identifier)</context>"
        if blocks.isEmpty {
            history.append(["role": "user", "content": text + ctx])
        } else {
            blocks.append(["type": "text", "text": text + ctx])
            history.append(["role": "user", "content": blocks])
        }
        busy = true
        status = L("Düşünüyor…")
        task = Task { @MainActor in
            await self.run()
            self.busy = false
            self.status = ""
            ChatStore.shared.save(id: self.chatID, items: self.items)
            if let title = self.scheduledTitle {
                self.scheduledTitle = nil
                let answer = self.items.last(where: { $0.role == .assistant })?.text ?? ""
                let line = answer.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? L("Tamamlandı")
                NotchModel.shared.showHUD(HUDInfo(icon: "sparkles", title: String(line.prefix(90)), leftText: title, wide: true,
                                                  tint: Prefs.shared.accentColor), seconds: 7)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { SpeechService.shared.resumeIfIdle() }
        }
    }

    @MainActor
    func stop() {
        task?.cancel()
        resolve(false)
    }

    @MainActor
    func reset() {
        stop()
        items = []
        history = []
        attachments = []
        chatID = UUID()
    }

    @MainActor
    private func run() async {
        for _ in 0..<16 {
            if Task.isCancelled { return }
            let resp: [String: Any]
            do {
                resp = try await ClaudeClient.send(messages: history, system: Self.fullSystemPrompt(), tools: ToolBox.definitions())
            } catch is CancellationError {
                repairHistory()
                return
            } catch {
                if (error as? URLError)?.code == .cancelled || Task.isCancelled { repairHistory(); return }
                items.append(ChatItem(role: .error, text: error.localizedDescription))
                repairHistory()
                return
            }

            let content = resp["content"] as? [[String: Any]] ?? []
            let stop = resp["stop_reason"] as? String ?? ""
            // Düşünme blokları dahil içerik olduğu gibi geri gönderilmelidir.
            if !content.isEmpty { history.append(["role": "assistant", "content": content]) }

            let text = content.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                items.append(ChatItem(role: .assistant, text: text))
                if stop != "tool_use" { SpeechService.shared.speakIfEnabled(text) }
            }

            switch stop {
            case "tool_use":
                var results: [[String: Any]] = []
                for block in content where block["type"] as? String == "tool_use" {
                    let name = block["name"] as? String ?? ""
                    let id = block["id"] as? String ?? ""
                    let input = block["input"] as? [String: Any] ?? [:]
                    status = ToolBox.label(name)
                    items.append(ChatItem(role: .tool, text: ToolBox.label(name)))
                    let out = Task.isCancelled ? ToolOutput.fail("Cancelled by user.") : await ToolBox.run(name, input)
                    var r: [String: Any] = ["type": "tool_result", "tool_use_id": id, "content": out.content]
                    if out.isError { r["is_error"] = true }
                    results.append(r)
                }
                history.append(["role": "user", "content": results])
                status = L("Düşünüyor…")
                continue
            case "pause_turn":
                continue
            case "refusal":
                items.append(ChatItem(role: .error, text: L("Claude bu isteği yanıtlamayı reddetti.")))
                // Reddedilen dönüşü geçmişten çıkar ki sohbet devam edebilsin.
                if !content.isEmpty { history.removeLast() }
                repairHistory()
                return
            case "max_tokens":
                items.append(ChatItem(role: .error, text: L("Yanıt uzunluk sınırına takıldı.")))
                return
            default:
                if text.isEmpty { items.append(ChatItem(role: .assistant, text: L("Tamam."))) }
                return
            }
        }
        items.append(ChatItem(role: .error, text: L("Çok fazla adım gerekti, durduruldu.")))
    }

    /// Geçmişin sonu yanıtsız bir kullanıcı mesajı ise onu çıkarır; aksi halde sonraki istek geçersiz olur.
    @MainActor
    private func repairHistory() {
        while let last = history.last, last["role"] as? String == "user" {
            history.removeLast()
            // Yalnızca araç sonucu taşıyan mesajların önündeki asistan mesajı da çıkarılır.
            let isToolResult = ((last["content"] as? [[String: Any]])?.first?["type"] as? String) == "tool_result"
            if !isToolResult { break }
            // tool_result'tan önceki tool_use içeren asistan mesajını da çıkar
            if let prev = history.last, prev["role"] as? String == "assistant" { history.removeLast() }
        }
    }

    // MARK: Onay

    @MainActor
    func confirm(title: String, detail: String) async -> Bool {
        await withCheckedContinuation { cont in
            pending = PendingConfirm(title: title, detail: detail, continuation: cont)
        }
    }

    @MainActor
    func resolve(_ ok: Bool) {
        guard let p = pending else { return }
        pending = nil
        p.continuation.resume(returning: ok)
    }
}

// MARK: - Ses: dikte ve seslendirme

final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    /// Sesli sohbet modu: susunca kendiliğinden gönderir, yanıtı okur ve yeniden dinler.
    @Published var conversation = false
    /// Sohbet modunda, konuşma bittiğinde çağrılır.
    var autoSend: ((String) -> Void)?
    private var lastChange = Date()
    private var silenceTimer: Timer?

    override init() {
        super.init()
        synth.delegate = self
    }

    func setConversation(_ on: Bool) {
        conversation = on
        if on {
            startListening()
        } else {
            stop()
            synth.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { if self.conversation { self.startListening() } }
    }

    /// Asistan yanıtını bitirdiğinde: okunacak bir şey yoksa yeniden dinlemeye geç.
    func resumeIfIdle() {
        if conversation, !listening, !synth.isSpeaking { startListening() }
    }

    private func checkSilence() {
        guard listening, conversation, !transcript.isEmpty, Date().timeIntervalSince(lastChange) > 1.5 else { return }
        let text = transcript
        stop()
        autoSend?(text)
    }

    @Published var listening = false
    @Published var transcript = ""
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private let synth = AVSpeechSynthesizer()

    func toggle(onFinish: @escaping (String) -> Void) {
        if listening {
            let text = transcript
            stop()
            onFinish(text)
        } else {
            startListening()
        }
    }

    func startListening() {
        guard !listening else { return }
        error = nil
        synth.stopSpeaking(at: .immediate)
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.error = L("Konuşma tanıma izni verilmedi.")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async {
                        guard ok else { self.error = L("Mikrofon izni verilmedi."); return }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: Prefs.shared.speechLocale)), rec.isAvailable else {
            error = L("Bu dil için konuşma tanıma kullanılamıyor.")
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { error = L("Mikrofon bulunamadı."); return }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            self.error = L("Mikrofon başlatılamadı.")
            return
        }
        transcript = ""
        listening = true
        lastChange = Date()
        silenceTimer?.invalidate()
        let st = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.checkSilence() }
        RunLoop.main.add(st, forMode: .common)
        silenceTimer = st
        recognition = rec.recognitionTask(with: req) { [weak self] result, _ in
            guard let self, let result else { return }
            DispatchQueue.main.async {
                if self.listening {
                    let t = result.bestTranscription.formattedString
                    if t != self.transcript { self.lastChange = Date() }
                    self.transcript = t
                }
            }
        }
    }

    func stop() {
        guard listening else { return }
        listening = false
        silenceTimer?.invalidate(); silenceTimer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognition?.cancel()
        request = nil
        recognition = nil
    }

    func speakIfEnabled(_ text: String) {
        guard Prefs.shared.speakReplies || conversation else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Prefs.shared.speechLocale)
        synth.speak(u)
    }

    func stopSpeaking() { synth.stopSpeaking(at: .immediate) }
}
