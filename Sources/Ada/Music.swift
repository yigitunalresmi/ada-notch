import AppKit
import SwiftUI

struct LyricLine: Equatable {
    var time: Double
    var text: String
}

final class MusicService: ObservableObject {
    static let shared = MusicService()

    enum Player: String {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"
        var name: String { self == .spotify ? "Spotify" : "Music" }
    }

    @Published var player: Player?
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var isPlaying = false
    @Published var duration: Double = 0
    @Published var position: Double = 0
    @Published var positionStamp = Date()
    @Published var artwork: NSImage?
    @Published var lyrics: [LyricLine] = []
    @Published var shuffle = false

    private var timer: Timer?
    private var busy = false
    private var trackKey = ""
    private static let sep = "|~|"

    var hasTrack: Bool { !title.isEmpty }

    var livePosition: Double {
        guard isPlaying else { return position }
        return min(duration, position + Date().timeIntervalSince(positionStamp))
    }

    func currentLyric(at pos: Double) -> String? {
        guard !lyrics.isEmpty else { return nil }
        var line: String?
        for l in lyrics where l.time <= pos + 0.2 { line = l.text }
        return line
    }

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            poll()
        } else if !on {
            timer?.invalidate()
            timer = nil
            clear()
        }
    }

    private func clear() {
        player = nil; title = ""; artist = ""; album = ""; isPlaying = false
        duration = 0; position = 0; artwork = nil; lyrics = []; trackKey = ""
    }

    private func statusScript(_ p: Player) -> String {
        let s = Self.sep.appleScriptQuoted
        let dur = p == .spotify ? "((duration of t) / 1000)" : "(duration of t)"
        let art = p == .spotify ? "(artwork url of t)" : "\"\""
        let shuf = p == .spotify ? "(shuffling as string)" : "(shuffle enabled as string)"
        return """
        tell application id "\(p.rawValue)"
            try
                set t to current track
                return (player state as string) & \(s) & (name of t) & \(s) & (artist of t) & \(s) & (album of t) & \(s) & \(dur) & \(s) & (player position) & \(s) & \(art) & \(s) & \(shuf)
            on error
                return "stopped"
            end try
        end tell
        """
    }

    private func poll() {
        guard !busy else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = [Player.spotify, .music].filter { running.contains($0.rawValue) }
        guard !candidates.isEmpty else {
            if player != nil { clear() }
            return
        }
        busy = true
        Script.queue.async {
            var best: (Player, [String])?
            for p in candidates {
                guard let out = Script.runSync(self.statusScript(p)).out?.stringValue else { continue }
                let parts = out.components(separatedBy: Self.sep)
                guard parts.count >= 7 else { continue }
                if parts[0] == "playing" { best = (p, parts); break }
                if best == nil { best = (p, parts) }
            }
            DispatchQueue.main.async {
                self.busy = false
                if let (p, parts) = best { self.apply(p, parts) } else if self.player != nil { self.clear() }
            }
        }
    }

    private func number(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func apply(_ p: Player, _ parts: [String]) {
        let playing = parts[0] == "playing"
        if player != p { player = p }
        if isPlaying != playing { isPlaying = playing }
        if title != parts[1] { title = parts[1] }
        if artist != parts[2] { artist = parts[2] }
        if album != parts[3] { album = parts[3] }
        let dur = number(parts[4])
        if duration != dur { duration = dur }
        position = number(parts[5])
        positionStamp = Date()
        let sh = parts.count > 7 && parts[7] == "true"
        if shuffle != sh { shuffle = sh }

        let key = "\(p.rawValue)|\(parts[1])|\(parts[2])"
        if key != trackKey {
            trackKey = key
            artwork = nil
            lyrics = []
            loadArtwork(p, urlString: parts[6], key: key)
            if Prefs.shared.isOn(.lyrics) { loadLyrics(key: key) }
        }
    }

    private func loadArtwork(_ p: Player, urlString: String, key: String) {
        if p == .spotify, let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { if self.trackKey == key { self.artwork = img } }
            }.resume()
        } else if p == .music {
            Script.queue.async {
                let src = "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
                guard let data = Script.runSync(src).out?.data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { if self.trackKey == key { self.artwork = img } }
            }
        }
    }

    private func loadLyrics(key: String) {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.setValue("Ada-Notch/0.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let synced = json["syncedLyrics"] as? String else { return }
            let lines = Self.parseLRC(synced)
            DispatchQueue.main.async { if self.trackKey == key { self.lyrics = lines } }
        }.resume()
    }

    static func parseLRC(_ text: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in text.components(separatedBy: "\n") {
            guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { continue }
            let stamp = raw[raw.index(after: raw.startIndex)..<close]
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { continue }
            let line = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
            out.append(LyricLine(time: m * 60 + s, text: line))
        }
        return out
    }

    // MARK: Komutlar

    private var target: Player? {
        if let player { return player }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return [Player.spotify, .music].first { running.contains($0.rawValue) }
    }

    @discardableResult
    func command(_ cmd: String) -> Bool {
        guard let p = target else { return false }
        Script.fire("tell application id \"\(p.rawValue)\" to \(cmd)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.poll() }
        return true
    }

    func togglePlay() { if command("playpause") { isPlaying.toggle() } }
    func toggleShuffle() {
        guard let p = target else { return }
        let prop = p == .spotify ? "shuffling" : "shuffle enabled"
        Script.fire("tell application id \"\(p.rawValue)\" to set \(prop) to not \(prop)")
        shuffle.toggle()
    }
    func next() { command("next track") }
    func previous() { command("previous track") }
    func seek(to seconds: Double) {
        command("set player position to \(Int(seconds))")
        position = seconds
        positionStamp = Date()
    }

    func openPlayer(_ p: Player) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.rawValue) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

// MARK: - Görünüm

struct MusicCard: View {
    @ObservedObject var music = MusicService.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        if music.hasTrack {
            GeometryReader { geo in
                let side = min(geo.size.height, 112)
                HStack(spacing: 14) {
                    ArtworkView(image: music.artwork, size: side, radius: 16)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                        .scaleEffect(music.isPlaying ? 1 : 0.92)
                        .id(music.title + music.artist + (music.artwork == nil ? "0" : "1"))
                        .transition(.blurReplace)
                        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: music.isPlaying)
                        .animation(.easeInOut(duration: 0.35), value: music.title)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(music.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(music.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            let pos = music.livePosition
                            VStack(alignment: .leading, spacing: 4) {
                                if prefs.isOn(.lyrics), let line = music.currentLyric(at: pos), !line.isEmpty {
                                    Text(line)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.green)
                                        .lineLimit(1)
                                        .id(line)
                                        .transition(.opacity)
                                }
                                HStack(spacing: 7) {
                                    Text(formatClock(pos))
                                    SeekBar(position: pos, duration: music.duration) { music.seek(to: $0) }
                                    Text(formatClock(music.duration))
                                }
                                .font(.system(size: 9.5).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 18) {
                            control("backward.fill", size: 14) { music.previous() }
                            control(music.isPlaying ? "pause.fill" : "play.fill", size: 21) { music.togglePlay() }
                            control("forward.fill", size: 14) { music.next() }
                            Button { music.toggleShuffle() } label: {
                                Image(systemName: "shuffle").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(music.shuffle ? Color.green : .white.opacity(0.45))
                                    .frame(width: 26, height: 26).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help(L("Karışık çal"))
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .clipped()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list").font(.system(size: 24)).foregroundStyle(.white.opacity(0.4))
                Text(L("Şu an çalan bir şey yok")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 8) {
                    Button(L("Spotify'ı aç")) { music.openPlayer(.spotify) }.buttonStyle(PillButtonStyle())
                    Button(L("Music'i aç")) { music.openPlayer(.music) }.buttonStyle(PillButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func control(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(HoverIconStyle())
    }
}

struct SeekBar: View {
    var position: Double
    var duration: Double
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let frac = duration > 0 ? min(1, max(0, position / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(.white).frame(width: max(4, geo.size.width * frac))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { g in
                guard duration > 0 else { return }
                onSeek(duration * min(1, max(0, g.location.x / geo.size.width)))
            })
        }
        .frame(height: 12)
    }
}
