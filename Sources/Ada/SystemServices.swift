import AppKit
import AudioToolbox
import CoreAudio
import CoreBluetooth
import IOBluetooth
import IOKit.ps
import SwiftUI

// MARK: - Pil

final class BatteryService: ObservableObject {
    static let shared = BatteryService()

    @Published var level: Int?
    @Published var onAC = false
    @Published var charging = false

    private var source: CFRunLoopSource?
    private var enabled = false
    private var primed = false
    private var chargeNotified = false

    var symbol: String {
        if onAC { return "battery.100.bolt" }
        guard let level else { return "battery.100" }
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            refresh()
            if source == nil {
                let src = IOPSNotificationCreateRunLoopSource({ _ in
                    DispatchQueue.main.async { BatteryService.shared.refresh() }
                }, nil).takeRetainedValue()
                CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
                source = src
            }
        } else {
            level = nil
            primed = false
        }
    }

    /// "Kalan süre: 3 sa 20 dk" gibi; bilinmiyorsa boş.
    var timeRemaining: String {
        let t = IOPSGetTimeRemainingEstimate()
        if t == -2 { return L("Güç adaptörüne bağlı") }
        guard t > 0 else { return L("Kalan süre hesaplanıyor") }
        let m = Int(t / 60)
        return Lf("Kalan süre: %@ sa %@ dk", "\(m / 60)", "\(m % 60)")
    }

    /// Takılı güç adaptörünün gücü, ör. " · 96W".
    private static func adapterWatts() -> String {
        guard let d = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let w = d["Watts"] as? Int, w > 0 else { return "" }
        return " · \(w)W"
    }

    func refresh() {
        guard enabled else { return }
        let snap = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snap).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let chg = d[kIOPSIsChargingKey] as? Bool ?? false
            let wasAC = onAC
            level = cap
            onAC = ac
            charging = chg
            if primed, ac != wasAC, Opt.flag("battery.plugHUD") {
                NotchModel.shared.showHUD(HUDInfo(
                    icon: ac ? "bolt.fill" : "battery.75",
                    title: ac ? Lf("Şarj oluyor · %%%@", "\(cap)") + Self.adapterWatts() : Lf("Pilde · %%%@", "\(cap)"),
                    tint: ac ? .green : .white), seconds: 2.6)
            }
            // Şarj hedefi: belirlenen düzeye ulaşınca bir kez haber ver.
            let target = Int(Opt.num("battery.notifyAt"))
            if !ac || cap < target { chargeNotified = false }
            if primed, ac, target > 0, cap >= target, !chargeNotified {
                chargeNotified = true
                NSSound(named: "Glass")?.play()
                NotchModel.shared.showHUD(HUDInfo(icon: "battery.100.bolt", title: Lf("Şarj %%%@ oldu — fişi çekebilirsiniz", "\(cap)"),
                                                  wide: true, tint: .green), seconds: 5)
            }
            if primed, !ac, cap == Int(Opt.num("battery.low")) || cap == 10 {
                NotchModel.shared.showHUD(HUDInfo(icon: "battery.25", title: Lf("Pil azaldı · %%%@", "\(cap)"), tint: .red), seconds: 3)
            }
            primed = true
            return
        }
    }
}

// MARK: - Bluetooth

final class BluetoothService: NSObject {
    static let shared = BluetoothService()
    private var note: IOBluetoothUserNotification?
    private var startedAt = Date()

    func setEnabled(_ on: Bool) {
        if on, note == nil {
            // Bluetooth izni açılışta istenmez; yalnızca zaten verilmişse dinlemeye başlanır.
            guard CBCentralManager.authorization == .allowedAlways else { return }
            startedAt = Date()
            note = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
        } else if !on, let n = note {
            n.unregister()
            note = nil
        }
    }

    /// Ayarlar › İzinler'deki düğmeyle çağrılır; macOS izin penceresini açar.
    func requestPermission() {
        guard note == nil else { return }
        startedAt = Date()
        note = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        // Kayıt anında zaten bağlı olan cihazlar için bildirim gösterme.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        let name = device.name ?? L("Bluetooth cihazı")
        DispatchQueue.main.async {
            NotchModel.shared.showHUD(HUDInfo(icon: Self.icon(for: name), title: Lf("%@ bağlandı", "\(name)"), tint: .blue), seconds: 2.8)
        }
        // Pil düzeyi birkaç saniye sonra hazır olur; ayrı bir bildirimle göster.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.2) {
            guard Opt.flag("bluetooth.battery"), let levels = BluetoothBattery.levels(for: name) else { return }
            DispatchQueue.main.async {
                NotchModel.shared.showHUD(HUDInfo(icon: Self.icon(for: name), title: levels, tint: .green), seconds: 3.2)
            }
        }
    }

    @objc private func disconnected(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        n.unregister()
        guard note != nil, Opt.flag("bluetooth.disconnect") else { return }
        let name = device.name ?? L("Bluetooth cihazı")
        DispatchQueue.main.async {
            NotchModel.shared.showHUD(HUDInfo(icon: Self.icon(for: name), title: Lf("%@ ayrıldı", "\(name)"), tint: .gray), seconds: 2.2)
        }
    }

    private static func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("keyboard") || n.contains("klavye") { return "keyboard" }
        if n.contains("mouse") || n.contains("trackpad") { return "computermouse" }
        return "headphones"
    }
}

// MARK: - Ses

enum Audio {
    static func defaultDevice() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    /// Ses çıkışı olan aygıtlar.
    static func outputDevices() -> [(id: AudioDeviceID, name: String)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        var out: [(AudioDeviceID, String)] = []
        for id in ids {
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var ssize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &ssize) == noErr, ssize > 0 else { continue }
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nsize, &name) == noErr, let n = name else { continue }
            out.append((id, n.takeRetainedValue() as String))
        }
        return out
    }

    @discardableResult
    static func setDefaultDevice(_ id: AudioDeviceID) -> Bool {
        var dev = id
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioDeviceID>.size), &dev) == noErr
    }

    static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static func volume() -> Float? {
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = volumeAddress
        let err = AudioObjectGetPropertyData(defaultDevice(), &addr, 0, nil, &size, &v)
        return err == noErr ? v : nil
    }

    static func setVolume(_ value: Float) -> Bool {
        var v = Float32(min(1, max(0, value)))
        var addr = volumeAddress
        let err = AudioObjectSetPropertyData(defaultDevice(), &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        return err == noErr
    }

    static func muted() -> Bool {
        var m = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = muteAddress
        AudioObjectGetPropertyData(defaultDevice(), &addr, 0, nil, &size, &m)
        return m != 0
    }

    static func setMuted(_ on: Bool) {
        var m = UInt32(on ? 1 : 0)
        var addr = muteAddress
        AudioObjectSetPropertyData(defaultDevice(), &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }
}

// MARK: - Parlaklık (özel DisplayServices çerçevesi; bulunamazsa sessizce devre dışı kalır)

enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func get() -> Float? {
        guard let handle, let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        let fn = unsafeBitCast(sym, to: GetFn.self)
        var v: Float = 0
        return fn(CGMainDisplayID(), &v) == 0 ? v : nil
    }

    static func set(_ value: Float) -> Bool {
        guard let handle, let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return false }
        let fn = unsafeBitCast(sym, to: SetFn.self)
        return fn(CGMainDisplayID(), min(1, max(0, value))) == 0
    }
}

// MARK: - Ses / parlaklık göstergesi

final class HUDService {
    static let shared = HUDService()
    private var enabled = false
    private var listened = Set<AudioDeviceID>()
    private var systemListening = false
    private var timer: Timer?
    private var lastBrightness: Float?
    /// Asistan sesi kendisi değiştirdiğinde gösterge çıkmasın diye.
    var suppressUntil = Date.distantPast

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            attach()
            if !systemListening {
                systemListening = true
                var addr = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
                    self?.attach()
                }
            }
            lastBrightness = Brightness.get()
            let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.pollBrightness() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate(); timer = nil
        }
    }

    private func attach() {
        let dev = Audio.defaultDevice()
        guard dev != 0, !listened.contains(dev) else { return }
        listened.insert(dev)
        var v = Audio.volumeAddress
        AudioObjectAddPropertyListenerBlock(dev, &v, .main) { [weak self] _, _ in self?.volumeChanged() }
        var m = Audio.muteAddress
        AudioObjectAddPropertyListenerBlock(dev, &m, .main) { [weak self] _, _ in self?.volumeChanged() }
    }

    private func volumeChanged() {
        guard enabled, Date() > suppressUntil, let v = Audio.volume() else { return }
        showVolume(v, muted: Audio.muted())
    }

    func showVolume(_ v: Float, muted isMuted: Bool) {
        let muted = isMuted || v < 0.005
        let icon = muted ? "speaker.slash.fill" : (v < 0.34 ? "speaker.wave.1.fill" : (v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
        NotchModel.shared.showHUD(HUDInfo(icon: icon, title: L("Ses"), value: muted ? 0 : Double(v)), seconds: Opt.num("hud.duration"))
    }

    private func pollBrightness() {
        guard enabled, let b = Brightness.get() else { return }
        defer { lastBrightness = b }
        // Parlaklık %100'ün altına indiyse ekstra parlaklığı kapat.
        if b < 0.99, BoostService.shared.factor > 1.001 { BoostService.shared.set(1) }
        guard let last = lastBrightness, abs(b - last) > 0.012, Date() > suppressUntil else { return }
        showBrightness(b)
    }

    func showBrightness(_ b: Float) {
        lastBrightness = b
        NotchModel.shared.showHUD(HUDInfo(icon: "sun.max.fill", title: L("Parlaklık"), value: Double(b), tint: .yellow), seconds: Opt.num("hud.duration"))
    }

    func showBoost() {
        let boost = BoostService.shared
        if boost.factor <= 1.001 {
            showBrightness(Brightness.get() ?? 1)
        } else {
            NotchModel.shared.showHUD(HUDInfo(icon: "sun.max.fill", title: "HDR", value: boost.fraction,
                                              label: "%\(Int((boost.factor * 100).rounded()))", tint: .orange), seconds: 1.8)
        }
    }
}

// MARK: - Sistem istatistikleri

final class StatsService: ObservableObject {
    static let shared = StatsService()

    @Published var cpu: Double = 0
    /// Son ölçümler (mini grafik için).
    @Published var cpuHistory: [Double] = []
    @Published var memUsed: Double = 0
    @Published var memTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published var netDown: Double = 0
    @Published var netUp: Double = 0

    private var timer: Timer?
    private var lastTicks: (busy: Double, total: Double)?
    private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?

    func setEnabled(_ on: Bool) {
        if on, timer == nil {
            let t = Timer(timeInterval: max(1, Opt.num("stats.interval")), repeats: true) { [weak self] _ in self?.sample() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            sample()
        } else if !on {
            timer?.invalidate(); timer = nil
        }
    }

    func sample() {
        // İşlemci
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let user = Double(load.cpu_ticks.0), sys = Double(load.cpu_ticks.1)
            let idle = Double(load.cpu_ticks.2), nice = Double(load.cpu_ticks.3)
            let busy = user + sys + nice, total = busy + idle
            if let last = lastTicks, total > last.total {
                cpu = (busy - last.busy) / (total - last.total)
                cpuHistory.append(cpu)
                if cpuHistory.count > 30 { cpuHistory.removeFirst(cpuHistory.count - 30) }
            }
            lastTicks = (busy, total)
        }

        // Bellek
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr2 = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if kr2 == KERN_SUCCESS {
            let page = Double(sysconf(_SC_PAGESIZE))
            memUsed = (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
        }

        // Ağ
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while let p = ptr {
                let name = String(cString: p.pointee.ifa_name)
                if let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                   name.hasPrefix("en"), let data = p.pointee.ifa_data {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(d.ifi_ibytes)
                    tx += UInt64(d.ifi_obytes)
                }
                ptr = p.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0, rx >= last.rx, tx >= last.tx {
                netDown = Double(rx - last.rx) / dt
                netUp = Double(tx - last.tx) / dt
            }
        }
        lastNet = (rx, tx, now)
    }

    static func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 { return String(format: "%.1f MB/s", bytesPerSec / 1_048_576) }
        return String(format: "%.0f KB/s", bytesPerSec / 1024)
    }
}
