import AppKit
import SwiftUI

/// Ada kaynak koddan derlenerek kurulur. Güncelleyici, kaynak klasöründeki git deposunu
/// kullanarak yeni sürümleri denetler; kurulum `git pull` ardından `./build.sh run` çalıştırır.
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(count: Int, notes: [String])
        case updating
        case failed(String)
        case unavailable(String)
    }

    @Published var state: State = .idle
    @Published var lastChecked: Date?

    private var timer: Timer?
    private var announced = false
    private let queue = DispatchQueue(label: "ada.updater")
    private let git = "/usr/bin/git"

    /// Bu kopyanın derlendiği commit.
    var commit: String { Bundle.main.infoDictionary?["AdaCommit"] as? String ?? "" }

    var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return commit.isEmpty ? "\(v) (\(b))" : "\(v) (\(b) · \(commit.prefix(7)))"
    }

    /// Kaynak deposunun klasörü: derleme sırasında kaydedilen yol, yoksa paketin iki üst klasörü.
    var sourcePath: String? {
        var candidates: [String] = []
        if let p = Bundle.main.infoDictionary?["AdaSourcePath"] as? String { candidates.append(p) }
        candidates.append(URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent().deletingLastPathComponent().path)
        return candidates.first {
            FileManager.default.fileExists(atPath: $0 + "/.git") && FileManager.default.fileExists(atPath: $0 + "/build.sh")
        }
    }

    var updateAvailable: Bool {
        if case .available = state { return true }
        return false
    }

    func start() {
        applySchedule()
        if Prefs.shared.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.check(silent: true) }
        }
    }

    func applySchedule() {
        timer?.invalidate(); timer = nil
        guard Prefs.shared.autoCheckUpdates else { return }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.check(silent: true) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// `silent`: sonuç yalnızca güncelleme varsa çentikte duyurulur.
    func check(silent: Bool = false) {
        if state == .checking || state == .updating { return }
        guard let src = sourcePath else {
            state = .unavailable(L("Bu kopya kaynak klasöründen çalışmıyor. Güncellemek için depoyu yeniden indirip derleyin."))
            return
        }
        state = .checking
        let built = commit
        queue.async {
            let fetch = Shell.run(self.git, ["-C", src, "fetch", "--quiet", "origin", "main"], timeout: 45)
            guard fetch.code == 0 else {
                DispatchQueue.main.async {
                    self.state = .failed(L("Güncelleme denetlenemedi (ağ ya da git hatası)."))
                    self.lastChecked = Date()
                }
                return
            }
            // Derlenen commit depoda bilinmiyorsa (ör. yerel değişiklik) HEAD ile karşılaştır.
            var base = built.isEmpty ? "HEAD" : built
            if Shell.run(self.git, ["-C", src, "cat-file", "-e", base + "^{commit}"]).code != 0 { base = "HEAD" }
            let count = Int(Shell.run(self.git, ["-C", src, "rev-list", "--count", base + "..origin/main"]).out) ?? 0
            let notes = Shell.run(self.git, ["-C", src, "log", "--format=%s", "-n", "6", base + "..origin/main"]).out
                .components(separatedBy: "\n").filter { !$0.isEmpty }
            DispatchQueue.main.async {
                self.lastChecked = Date()
                if count > 0 {
                    self.state = .available(count: count, notes: notes)
                    if Prefs.shared.autoInstallUpdates {
                        self.install()
                    } else if !self.announced {
                        self.announced = true
                        NotchModel.shared.showHUD(HUDInfo(icon: "arrow.down.circle.fill", title: L("Ada güncellemesi var"), tint: .blue), seconds: 3.5)
                    }
                } else {
                    self.state = .upToDate
                }
            }
        }
    }

    /// Yeni sürümü indirir, derler ve Ada'yı yeniden başlatır. Derleme başarısız olursa çalışan sürüm aynen kalır.
    func install() {
        guard state != .updating, let src = sourcePath else { return }
        state = .updating
        let log = NSHomeDirectory() + "/Library/Logs/Ada-update.log"
        FileManager.default.createFile(atPath: log, contents: nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Yerel değişiklik varsa `--ff-only` üzerine yazmak yerine durur.
        p.arguments = ["-lc", "cd \"$0\" && /usr/bin/git pull --ff-only origin main && ./build.sh run", src]
        if let handle = FileHandle(forWritingAtPath: log) {
            p.standardOutput = handle
            p.standardError = handle
        }
        p.terminationHandler = { proc in
            // Başarılı olursa build.sh Ada'yı kapatıp yeniden açar; buraya yalnızca hata durumunda gelinir.
            guard proc.terminationStatus != 0 else { return }
            let tail = (try? String(contentsOfFile: log, encoding: .utf8))?
                .components(separatedBy: "\n").filter { !$0.isEmpty }.suffix(3).joined(separator: "\n") ?? ""
            DispatchQueue.main.async { self.state = .failed(L("Güncelleme kurulamadı.") + (tail.isEmpty ? "" : "\n" + tail)) }
        }
        do { try p.run() } catch {
            state = .failed(L("Güncelleme başlatılamadı."))
        }
    }
}

// MARK: - Ayarlar sayfası

struct UpdatesSettings: View {
    @ObservedObject var updater = Updater.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppBadge(size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ada").font(.title2.weight(.semibold))
                        Text(Lf("Sürüm %@", updater.versionText)).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: 10) {
                    statusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle).fontWeight(.medium)
                        if let detail = statusDetail {
                            Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Spacer()
                    if updater.updateAvailable {
                        Button(L("Şimdi güncelle")) { updater.install() }.buttonStyle(.borderedProminent)
                    } else {
                        Button(L("Denetle")) { updater.check() }
                            .disabled(updater.state == .checking || updater.state == .updating)
                    }
                }
                if case let .available(_, notes) = updater.state, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Yenilikler")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(notes, id: \.self) { n in
                            Label(n, systemImage: "sparkle").font(.callout)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(L("Güncellemeler"))
            } footer: {
                Text(L("Ada kaynak koddan kurulduğu için güncelleme, depodaki yeni sürümü indirip Mac'inizde yeniden derler ve Ada'yı yeniden başlatır. Derleme başarısız olursa çalışan sürüm değişmez."))
            }

            Section {
                Toggle(L("Güncellemeleri otomatik denetle"), isOn: $prefs.autoCheckUpdates)
                Toggle(L("Yeni sürümleri otomatik kur"), isOn: $prefs.autoInstallUpdates)
                    .disabled(!prefs.autoCheckUpdates)
            } footer: {
                Text(L("Otomatik kurulum açıkken Ada, depodan gelen kodu size sormadan derleyip çalıştırır."))
            }

            Section {
                Link(destination: URL(string: "https://github.com/yigitunalresmi/ada-notch")!) {
                    Label(L("GitHub'da görüntüle"), systemImage: "arrow.up.right.square")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: prefs.autoCheckUpdates) { _, _ in updater.applySchedule() }
    }

    @ViewBuilder private var statusIcon: some View {
        switch updater.state {
        case .checking, .updating: ProgressView().controlSize(.small).frame(width: 22)
        case .available: Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.blue)
        case .upToDate: Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
        case .failed, .unavailable: Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange)
        case .idle: Image(systemName: "arrow.triangle.2.circlepath").font(.title2).foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        switch updater.state {
        case .idle: return L("Henüz denetlenmedi")
        case .checking: return L("Denetleniyor…")
        case .upToDate: return L("Ada güncel")
        case let .available(count, _): return Lf("%@ yeni güncelleme var", "\(count)")
        case .updating: return L("Güncelleniyor… Ada birazdan yeniden başlayacak")
        case .failed: return L("Bir sorun oluştu")
        case .unavailable: return L("Güncelleyici kullanılamıyor")
        }
    }

    private var statusDetail: String? {
        switch updater.state {
        case let .failed(message), let .unavailable(message): return message
        case .upToDate, .available:
            guard let d = updater.lastChecked else { return nil }
            let f = DateFormatter()
            f.locale = appLocale
            f.dateStyle = .none
            f.timeStyle = .short
            return Lf("Son denetim: %@", f.string(from: d))
        default: return nil
        }
    }
}

/// Uygulamanın küçük logosu: tema renklerinde yuvarlak kare içinde kıvılcım.
struct AppBadge: View {
    var size: CGFloat
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [prefs.themeColor1, prefs.themeColor2], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "sparkle").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: prefs.themeColor1.opacity(0.4), radius: size * 0.14, y: size * 0.06)
    }
}
