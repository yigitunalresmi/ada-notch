import AppKit
import Combine
import CoreAudio
import SQLite3
import SwiftUI

// Bu dosyadaki modüller macOS'in korumalı alanlarına ya da belgelenmemiş arayüzlerine dayanır;
// hepsi varsayılan olarak kapalıdır ve bir macOS güncellemesiyle çalışmayı bırakabilir.

// MARK: - Tam Disk Erişimi

enum FullDiskAccess {
    static var focusDir: String { NSHomeDirectory() + "/Library/DoNotDisturb/DB" }

    /// Korumalı bir klasör listelenebiliyorsa izin verilmiştir.
    static var granted: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: focusDir)) != nil
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Odak modu

final class FocusService: ObservableObject {
    static let shared = FocusService()

    struct Mode: Equatable {
        var name: String
        var symbol: String
    }

    @Published var current: Mode?
    @Published var readable = true

    private var timer: Timer?
    private var primed = false
    private var lastStamp: Date?

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            primed = false
            lastStamp = nil
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            poll()
        } else if !on {
            timer?.invalidate(); timer = nil
            current = nil
        }
    }

    private func poll() {
        let path = FullDiskAccess.focusDir + "/Assertions.json"
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            if readable { readable = false }
            return
        }
        if !readable { readable = true }
        let stamp = attrs[.modificationDate] as? Date
        if primed, stamp == lastStamp { return }
        lastStamp = stamp

        let mode = Self.readMode()
        let was = current
        if mode != current { current = mode }
        if primed, mode != was {
            if let mode {
                NotchModel.shared.showHUD(HUDInfo(icon: mode.symbol, title: Lf("%@ açık", mode.name), tint: .indigo), seconds: 2.6)
            } else if let was {
                NotchModel.shared.showHUD(HUDInfo(icon: "moon", title: Lf("%@ kapandı", was.name), tint: .gray), seconds: 2.2)
            }
        }
        primed = true
    }

    private static func json(_ file: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: FullDiskAccess.focusDir + "/" + file) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func readMode() -> Mode? {
        guard let root = json("Assertions.json"),
              let data = (root["data"] as? [[String: Any]])?.first,
              let records = data["storeAssertionRecords"] as? [[String: Any]],
              let details = records.first?["assertionDetails"] as? [String: Any],
              let id = details["assertionDetailsModeIdentifier"] as? String else { return nil }

        // Mod adını ve simgesini yapılandırma dosyasından bul.
        if let conf = json("ModeConfigurations.json"),
           let cdata = (conf["data"] as? [[String: Any]])?.first,
           let modes = cdata["modeConfigurations"] as? [String: Any],
           let entry = modes[id] as? [String: Any],
           let mode = entry["mode"] as? [String: Any] {
            let name = mode["name"] as? String ?? L("Odak")
            let symbol = mode["symbolImageName"] as? String ?? "moon.fill"
            return Mode(name: name, symbol: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : "moon.fill")
        }
        return Mode(name: id.contains("donotdisturb") ? L("Rahatsız Etme") : L("Odak"), symbol: "moon.fill")
    }
}

// MARK: - Bildirimleri çentikte gösterme

final class NotificationWatcher: ObservableObject {
    static let shared = NotificationWatcher()

    /// nil: sorun yok. Aksi halde kullanıcıya gösterilecek açıklama.
    @Published var problem: String?

    private var timer: Timer?
    private var lastID: Int64 = -1
    private let queue = DispatchQueue(label: "ada.notifications")

    private static var dbPath: String? {
        let candidates = [
            NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db",
            (NSTemporaryDirectory() as NSString).deletingLastPathComponent + "/0/com.apple.notificationcenter/db2/db",
        ]
        return candidates.first { FileManager.default.isReadableFile(atPath: $0) }
    }

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            lastID = -1
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            poll()
        } else if !on {
            timer?.invalidate(); timer = nil
            problem = nil
        }
    }

    private func setProblem(_ p: String?) {
        DispatchQueue.main.async { if self.problem != p { self.problem = p } }
    }

    private func poll() {
        queue.async {
            guard let path = Self.dbPath else {
                self.setProblem(L("Bildirim veritabanı okunamıyor. Tam Disk Erişimi gerekli."))
                return
            }
            var db: OpaquePointer?
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
                self.setProblem(L("Bildirim veritabanı açılamadı."))
                return
            }
            defer { sqlite3_close(db) }

            if self.lastID < 0 {
                // İlk çalıştırmada eski bildirimleri gösterme; yalnızca son kimliği al.
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(rec_id), 0) FROM record", -1, &stmt, nil) == SQLITE_OK else {
                    self.setProblem(L("Bildirim veritabanının biçimi tanınmadı."))
                    return
                }
                if sqlite3_step(stmt) == SQLITE_ROW { self.lastID = sqlite3_column_int64(stmt, 0) }
                sqlite3_finalize(stmt)
                self.setProblem(nil)
                return
            }

            var stmt: OpaquePointer?
            let sql = "SELECT r.rec_id, a.identifier, r.data FROM record r LEFT JOIN app a ON a.app_id = r.app_id WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT 5"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                self.setProblem(L("Bildirim veritabanının biçimi tanınmadı."))
                return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, self.lastID)
            var found: [(bundle: String, title: String, body: String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                self.lastID = sqlite3_column_int64(stmt, 0)
                let bundle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                guard let blob = sqlite3_column_blob(stmt, 2) else { continue }
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 2)))
                guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let req = plist["req"] as? [String: Any] else { continue }
                let title = (req["titl"] as? String) ?? ""
                let subtitle = (req["subt"] as? String) ?? ""
                let body = (req["body"] as? String) ?? ""
                let text = [subtitle, body].filter { !$0.isEmpty }.joined(separator: " — ")
                if title.isEmpty, text.isEmpty { continue }
                found.append(((plist["app"] as? String) ?? bundle, title, text))
            }
            self.setProblem(nil)
            guard let last = found.last else { return }
            DispatchQueue.main.async { self.show(last) }
        }
    }

    private func show(_ n: (bundle: String, title: String, body: String)) {
        guard n.bundle != Bundle.main.bundleIdentifier else { return }
        // Odak modu açıkken gelen bildirimleri gösterme (isteğe bağlı).
        if Opt.flag("notifications.quietInFocus"), Prefs.shared.isOn(.focus), FocusService.shared.current != nil { return }
        var image: NSImage?
        var appName = ""
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: n.bundle) {
            image = NSWorkspace.shared.icon(forFile: url.path)
            appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        // Yok sayılan uygulamalar
        let ignored = Opt.list("notifications.ignore").map { $0.lowercased() }
        if ignored.contains(appName.lowercased()) || ignored.contains(n.bundle.lowercased()) { return }
        let sender = n.title.isEmpty ? appName : n.title
        NotchModel.shared.showHUD(HUDInfo(icon: "bell.fill", title: (n.body.isEmpty || Opt.flag("notifications.hideBody")) ? appName : n.body,
                                          image: image, leftText: sender, wide: true), seconds: Opt.num("notifications.duration"))
    }
}

// MARK: - Gerçek ses görselleştirici (sistem sesi)

/// Sistemin çaldığı sesi dinleyip dört frekans bandının düzeyini verir. Ses kaydedilmez, saklanmaz.
final class AudioVisualizer: ObservableObject {
    static let shared = AudioVisualizer()

    @Published var levels: [Float] = [0, 0, 0, 0]
    @Published var active = false
    /// Ayarlardaki hassasiyet çarpanı (ana iş parçacığından güncellenir).
    static var gainScale: Float = 1

    private var enabled = false
    private var bag = Set<AnyCancellable>()
    private var tap: AnyObject?

    func setEnabled(_ on: Bool) {
        enabled = on
        if bag.isEmpty {
            MusicService.shared.$isPlaying.removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.update() }
                .store(in: &bag)
        }
        update()
    }

    /// Yalnızca müzik çalarken dinler.
    private func update() {
        let want = enabled && MusicService.shared.isPlaying
        if want, tap == nil {
            guard #available(macOS 14.2, *) else { return }
            let t = SystemAudioTap()
            t.onLevels = { [weak self] l in
                DispatchQueue.main.async { self?.levels = l }
            }
            if t.start() {
                tap = t
                active = true
            }
        } else if !want, let t = tap {
            if #available(macOS 14.2, *) { (t as? SystemAudioTap)?.stop() }
            tap = nil
            active = false
            levels = [0, 0, 0, 0]
        }
    }
}

@available(macOS 14.2, *)
final class SystemAudioTap {
    var onLevels: (([Float]) -> Void)?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "ada.audiotap", qos: .userInitiated)

    // Dört bantlı basit süzgeç bankası
    private var lp: [Float] = [0, 0, 0]
    private var smooth: [Float] = [0, 0, 0, 0]
    private var lastEmit = DispatchTime.now()

    private static func defaultOutputUID() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(Audio.defaultDevice(), &addr, 0, nil, &size, &uid) == noErr, let u = uid else { return nil }
        return u.takeRetainedValue() as String
    }

    func start() -> Bool {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr, let outUID = Self.defaultOutputUID() else {
            stop()
            return false
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Ada Visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            stop()
            return false
        }
        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, inData, _, _, _ in
            self?.process(inData)
        }
        guard err == noErr, AudioDeviceStart(aggregateID, procID) == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func process(_ list: UnsafePointer<AudioBufferList>) {
        let buffer = list.pointee.mBuffers
        guard let raw = buffer.mData, buffer.mDataByteSize > 0 else { return }
        let channels = max(1, Int(buffer.mNumberChannels))
        let total = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
        let samples = raw.assumingMemoryBound(to: Float32.self)

        // Kesim frekansları yaklaşık 150 Hz, 700 Hz ve 3 kHz (48 kHz örnekleme için).
        let a: [Float] = [0.0194, 0.0876, 0.3248]
        var energy: [Float] = [0, 0, 0, 0]
        var n: Float = 0
        var i = 0
        while i < total {
            let x = samples[i]
            lp[0] += a[0] * (x - lp[0])
            lp[1] += a[1] * (x - lp[1])
            lp[2] += a[2] * (x - lp[2])
            let b0 = lp[0], b1 = lp[1] - lp[0], b2 = lp[2] - lp[1], b3 = x - lp[2]
            energy[0] += b0 * b0
            energy[1] += b1 * b1
            energy[2] += b2 * b2
            energy[3] += b3 * b3
            n += 1
            i += channels
        }
        guard n > 0 else { return }
        let gains: [Float] = [3.2, 4.5, 7.0, 12.0]
        for k in 0..<4 {
            let level = min(1, (energy[k] / n).squareRoot() * gains[k] * AudioVisualizer.gainScale)
            smooth[k] = max(level, smooth[k] * 0.82)
        }
        let now = DispatchTime.now()
        if now.uptimeNanoseconds - lastEmit.uptimeNanoseconds > 40_000_000 {
            lastEmit = now
            onLevels?(smooth)
        }
    }
}

// MARK: - Kilit ekranında görünme (belgelenmemiş SkyLight arayüzü)

enum LockScreen {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static var space: Int32 = 0
    private(set) static var attached = false

    /// Pencereyi kilit ekranının üstünde duran ayrı bir alana taşır. Başarısız olursa hiçbir şey değişmez.
    @discardableResult
    static func attach(_ window: NSWindow) -> Bool {
        guard !attached,
              let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let cSym = dlsym(h, "SLSMainConnectionID"), let createSym = dlsym(h, "SLSSpaceCreate"),
              let levelSym = dlsym(h, "SLSSpaceSetAbsoluteLevel"), let showSym = dlsym(h, "SLSShowSpaces"),
              let addSym = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return false }
        let connection = unsafeBitCast(cSym, to: MainConnection.self)()
        if space == 0 {
            space = unsafeBitCast(createSym, to: SpaceCreate.self)(connection, 1, 0)
            guard space != 0 else { return false }
            _ = unsafeBitCast(levelSym, to: SpaceSetLevel.self)(connection, space, 400)
            _ = unsafeBitCast(showSym, to: ShowSpaces.self)(connection, [space] as CFArray)
        }
        _ = unsafeBitCast(addSym, to: AddWindows.self)(connection, space, [window.windowNumber] as CFArray, 7)
        attached = true
        return true
    }
}
