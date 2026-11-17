import AppKit
import ApplicationServices
import MetalKit

// MARK: - Ses ve parlaklık tuşlarını yakalama
//
// Tuşlar sisteme ulaşmadan yakalanır; böylece macOS'in kendi göstergesi çıkmaz,
// yerine Ada'nın çentikteki göstergesi görünür. Erişilebilirlik izni gerektirir.

final class MediaKeyTap {
    static let shared = MediaKeyTap()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var trustTimer: Timer?
    private var wanted = false
    private var prompted = false

    var active: Bool { tap != nil }
    var trusted: Bool { AXIsProcessTrusted() }

    func setEnabled(_ on: Bool) {
        wanted = on
        if on {
            install()
        } else {
            trustTimer?.invalidate(); trustTimer = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            tap = nil; source = nil
        }
    }

    func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func install() {
        guard wanted, tap == nil else { return }
        guard AXIsProcessTrusted() else {
            if !prompted { prompted = true; requestTrust() }
            if trustTimer == nil {
                let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.install() }
                RunLoop.main.add(t, forMode: .common)
                trustTimer = t
            }
            return
        }
        trustTimer?.invalidate(); trustTimer = nil

        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = MediaKeyTap.shared.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return MediaKeyTap.shared.handle(event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback, userInfo: nil) else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
    }

    /// Olay Ada tarafından işlendiyse (ve sisteme iletilmemesi gerekiyorsa) true döner.
    private func handle(_ cg: CGEvent) -> Bool {
        guard let e = NSEvent(cgEvent: cg), e.type == .systemDefined, e.subtype.rawValue == 8 else { return false }
        let key = (e.data1 & 0xFFFF_0000) >> 16
        let down = ((e.data1 & 0xFF00) >> 8) == 0xA
        let fine = e.modifierFlags.contains([.option, .shift])
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16

        switch key {
        case 0, 1, 7: // ses aç, ses kıs, sessiz
            guard Audio.volume() != nil else { return false }
            if down { changeVolume(key: key, step: step) }
            return true
        case 2, 3: // parlaklık artır, azalt
            guard Brightness.get() != nil else { return false }
            if down { changeBrightness(up: key == 2, step: step) }
            return true
        default:
            return false
        }
    }

    private func changeVolume(key: Int, step: Float) {
        var v = Audio.volume() ?? 0
        var muted = Audio.muted()
        if key == 7 {
            muted.toggle()
            Audio.setMuted(muted)
        } else {
            v = min(1, max(0, v + (key == 0 ? step : -step)))
            // Kayan nokta hatası birikmesin diye adıma yuvarla.
            v = (v / step).rounded() * step
            _ = Audio.setVolume(v)
            if muted, key == 0 { muted = false; Audio.setMuted(false) }
        }
        HUDService.shared.showVolume(v, muted: muted)
    }

    private func changeBrightness(up: Bool, step: Float) {
        let boost = BoostService.shared
        let b = Brightness.get() ?? 0
        let canBoost = Prefs.shared.isOn(.xdr) && boost.available

        if up, b >= 0.999, canBoost {
            boost.set(boost.factor + boost.step)
        } else if !up, boost.factor > 1.001 {
            boost.set(boost.factor - boost.step)
        } else {
            var nb = min(1, max(0, b + (up ? step : -step)))
            nb = (nb / step).rounded() * step
            _ = Brightness.set(nb)
            HUDService.shared.showBrightness(nb)
            return
        }
        HUDService.shared.showBoost()
    }
}

// MARK: - XDR ekstra parlaklık
//
// Çentiğin arkasında kalan 2 noktalık küçük bir HDR katmanı, ekranın HDR (EDR) aralığını
// açık tutar. Parlaklık artışı ise ekranın gama tablosu ölçeklenerek yapılır. Tam ekranı
// kaplayan bir katman kullanılmaz; bu yüzden ekranın beyaza dönmesi mümkün değildir.

final class BoostWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class BoostView: MTKView, MTKViewDelegate {
    private var queue: MTLCommandQueue?

    init(frame: NSRect) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        queue = device?.makeCommandQueue()
        delegate = self
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        preferredFramesPerSecond = 2
        // 1'den büyük değer: sistemin HDR aralığını açması için yeterli.
        clearColor = MTLClearColorMake(2, 2, 2, 1)
        if let l = layer as? CAMetalLayer {
            l.wantsExtendedDynamicRangeContent = true
            l.pixelFormat = .rgba16Float
        }
    }

    required init(coder: NSCoder) { fatalError() }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
              let buffer = queue?.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Ekranın gama tablosunu yönetir: ekstra (HDR) parlaklık, renk sıcaklığı, kontrast ve ek karartma.
final class BoostService: ObservableObject {
    static let shared = BoostService()

    /// Ekstra parlaklık hedefi. 1.0 = normal; en fazla `maxFactor`.
    @Published private(set) var factor: Double = 1.0
    let step = 0.1

    private var window: BoostWindow?
    private var timer: Timer?
    private var observing = false
    /// Hedefe doğru yumuşakça ilerleyen parlaklık değeri.
    private var rendered = 1.0
    /// Tabloya en son uygulanan ayarların özeti (gereksiz yazmayı önler).
    private var signature = ""
    private var displayID: CGDirectDisplayID = 0
    private var baseR: [CGGammaValue] = [], baseG: [CGGammaValue] = [], baseB: [CGGammaValue] = []

    private var edrScreen: NSScreen? {
        NSScreen.screens.first { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.05 }
    }
    private var targetScreen: NSScreen? { edrScreen ?? NSScreen.main ?? NSScreen.screens.first }

    var available: Bool { edrScreen != nil }

    var maxFactor: Double {
        guard let s = edrScreen else { return 1 }
        return min(Prefs.shared.hdrMax, Double(s.maximumPotentialExtendedDynamicRangeColorComponentValue))
    }

    /// 0…1: ek parlaklık aralığının ne kadarı kullanılıyor.
    var fraction: Double { maxFactor > 1 ? (factor - 1) / (maxFactor - 1) : 0 }

    private var tuning: Bool {
        let p = Prefs.shared
        return p.warmth > 0.005 || abs(p.contrast) > 0.005 || p.dim > 0.005
    }

    func set(_ value: Double) {
        let f = min(maxFactor, max(1, (value * 100).rounded() / 100))
        if f != factor { factor = f }
        refresh()
    }

    /// Parlaklık hedefi ya da ekran ayarları değiştiğinde çağrılır.
    func refresh() {
        observe()
        if factor > 1.001 {
            guard captureBase() else { return }
            startBoost()
        } else if timer == nil {
            applyTable(boost: 1)
        }
    }

    private func observe() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(self, selector: #selector(displayReset),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayReset),
                                                          name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    /// Değiştirmeden önce ekranın kendi gama tablosunu saklar.
    private func captureBase() -> Bool {
        if !baseR.isEmpty { return true }
        guard let s = targetScreen,
              let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
        var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, 256, &r, &g, &b, &count) == .success, count > 1 else { return false }
        displayID = id
        baseR = Array(r.prefix(Int(count))); baseG = Array(g.prefix(Int(count))); baseB = Array(b.prefix(Int(count)))
        signature = ""
        return true
    }

    private func startBoost() {
        guard window == nil, let s = edrScreen else { return }
        // Fiziksel çentiğin arkasında kalan, görünmeyen küçük HDR katmanı.
        let frame = NSRect(x: s.frame.midX - 1, y: s.frame.maxY - 3, width: 2, height: 2)
        let w = BoostWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.animationBehavior = .none
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        w.contentView = BoostView(frame: NSRect(origin: .zero, size: frame.size))
        w.setFrame(frame, display: true)
        w.orderFrontRegardless()
        window = w
        rendered = 1
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        // Hedefe yumuşak geçiş (tam aralık yaklaşık 0,8 sn).
        let delta = factor - rendered
        let speed = 0.025
        rendered = abs(delta) <= speed ? factor : rendered + (delta > 0 ? speed : -speed)

        // Sistem HDR aralığını kademeli açar; o an izin verilenden fazlasını isteme.
        let headroom = Double(edrScreen?.maximumExtendedDynamicRangeColorComponentValue ?? 1)
        applyTable(boost: max(1, min(rendered, headroom)))

        if factor <= 1.001, rendered <= 1.001 {
            timer?.invalidate(); timer = nil
            window?.orderOut(nil)
            window = nil
            rendered = 1
            applyTable(boost: 1)
        }
    }

    private func applyTable(boost: Double) {
        let p = Prefs.shared
        if boost <= 1.001, !tuning {
            restore()
            return
        }
        guard captureBase() else { return }
        let sig = String(format: "%.3f|%.3f|%.3f|%.3f", boost, p.warmth, p.contrast, p.dim)
        guard sig != signature else { return }
        signature = sig

        let dim: Double = min(0.8, max(0.0, p.dim))
        let scale: Double = boost * (1.0 - dim)
        let gainG: Double = 1.0 - 0.22 * p.warmth
        let gainB: Double = 1.0 - 0.55 * p.warmth
        let c: Double = 1.0 + p.contrast
        func table(_ base: [CGGammaValue], _ gain: Double) -> [CGGammaValue] {
            var out = [CGGammaValue]()
            out.reserveCapacity(base.count)
            for v in base {
                let centered: Double = (Double(v) - 0.5) * c + 0.5
                let curved: Double = min(1.0, max(0.0, centered))
                out.append(CGGammaValue(curved * gain * scale))
            }
            return out
        }
        var r = table(baseR, 1.0), g = table(baseG, gainG), b = table(baseB, gainB)
        CGSetDisplayTransferByTable(displayID, UInt32(r.count), &r, &g, &b)
    }

    /// Ekranın gama tablosunu ilk haline döndürür.
    func restore() {
        guard !baseR.isEmpty else { return }
        var r = baseR, g = baseG, b = baseB
        CGSetDisplayTransferByTable(displayID, UInt32(r.count), &r, &g, &b)
        baseR = []; baseG = []; baseB = []
        signature = ""
    }

    /// Ekran yeniden yapılandırıldığında ya da uyandığında sistem gama tablosunu sıfırlar; yeniden uygula.
    @objc private func displayReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            if self.window != nil, self.edrScreen == nil {
                self.factor = 1
                self.timer?.invalidate(); self.timer = nil
                self.window?.orderOut(nil); self.window = nil
                self.rendered = 1
            }
            guard !self.baseR.isEmpty else { return }
            self.signature = ""
            if self.timer == nil { self.applyTable(boost: 1) }
        }
    }
}
