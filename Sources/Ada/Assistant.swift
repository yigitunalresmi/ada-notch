import AVFoundation
import AppKit
import Foundation
import Security
import Speech

// MARK: - Anahtar zinciri

enum Keychain {
    private static let service = "app.ada.notch"
    private static let account = "anthropic-api-key"

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
        ("claude-opus-5-5", "Claude Opus 5.5 (önerilen)"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5 (daha hızlı, daha ucuz)"),
        ("claude-haiku-5-5", "Claude Haiku 5.5 (en hızlı)"),
    ]

    static func send(messages: [[String: Any]], system: String, tools: [[String: Any]]) async throws -> [String: Any] {
        guard let key = Keychain.get(), !key.isEmpty else {
            throw ClaudeError(status: 0, message: "API anahtarı girilmemiş. Ayarlar › Asistan bölümünden ekleyin.")
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

        var lastError: Error = ClaudeError(status: 0, message: "Bağlantı kurulamadı.")
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
                case 401: err = ClaudeError(status: status, message: "API anahtarı geçersiz. Ayarlar › Asistan bölümünden kontrol edin.")
                case 403: err = ClaudeError(status: status, message: "Bu anahtarın bu modele erişim izni yok: \(detail)")
                case 429: err = ClaudeError(status: status, message: "İstek sınırına ulaşıldı, biraz sonra tekrar deneyin.")
                case 500...599: err = ClaudeError(status: status, message: "Claude şu an yoğun (\(status)). Biraz sonra tekrar deneyin.")
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
                lastError = ClaudeError(status: 0, message: "Ağ hatası: \(error.localizedDescription)")
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
    @Published var hasKey = (Keychain.get() ?? "").isEmpty == false

    private var history: [[String: Any]] = []
    private var task: Task<Void, Never>?

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
    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        items.append(ChatItem(role: .user, text: text))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm EEEE"
        let ctx = "\n\n<context>now: \(f.string(from: Date())), timezone: \(TimeZone.current.identifier)</context>"
        history.append(["role": "user", "content": text + ctx])
        busy = true
        status = "Düşünüyor…"
        task = Task { @MainActor in
            await self.run()
            self.busy = false
            self.status = ""
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
                status = "Düşünüyor…"
                continue
            case "pause_turn":
                continue
            case "refusal":
                items.append(ChatItem(role: .error, text: "Claude bu isteği yanıtlamayı reddetti."))
                // Reddedilen dönüşü geçmişten çıkar ki sohbet devam edebilsin.
                if !content.isEmpty { history.removeLast() }
                repairHistory()
                return
            case "max_tokens":
                items.append(ChatItem(role: .error, text: "Yanıt uzunluk sınırına takıldı."))
                return
            default:
                if text.isEmpty { items.append(ChatItem(role: .assistant, text: "Tamam.")) }
                return
            }
        }
        items.append(ChatItem(role: .error, text: "Çok fazla adım gerekti, durduruldu."))
    }

    /// Geçmişin sonu yanıtsız bir kullanıcı mesajı ise onu çıkarır; aksi halde sonraki istek geçersiz olur.
    @MainActor
    private func repairHistory() {
        while let last = history.last, last["role"] as? String == "user" {
            history.removeLast()
            if last["content"] is String { break }
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
                    self.error = "Konuşma tanıma izni verilmedi."
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async {
                        guard ok else { self.error = "Mikrofon izni verilmedi."; return }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: Prefs.shared.speechLocale)), rec.isAvailable else {
            error = "Bu dil için konuşma tanıma kullanılamıyor."
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { error = "Mikrofon bulunamadı."; return }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            self.error = "Mikrofon başlatılamadı."
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
