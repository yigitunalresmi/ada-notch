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

final class BoostService: ObservableObject {
    static let shared = BoostService()

    /// Hedef değer. 1.0 = normal; en fazla `maxFactor`.
    @Published private(set) var factor: Double = 1.0
    let step = 0.1

    private var window: BoostWindow?
    private var timer: Timer?
    private var observing = false
    /// Hedefe doğru yumuşakça ilerleyen değer.
    private var rendered = 1.0
    /// Gama tablosuna en son uygulanan değer.
    private var applied = 1.0
    private var displayID: CGDirectDisplayID = 0
    private var baseR: [CGGammaValue] = [], baseG: [CGGammaValue] = [], baseB: [CGGammaValue] = []

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.05 }
    }

    var available: Bool { screen != nil }

    var maxFactor: Double {
        guard let s = screen else { return 1 }
        return min(Prefs.shared.hdrMax, Double(s.maximumPotentialExtendedDynamicRangeColorComponentValue))
    }

    /// 0…1: ek parlaklık aralığının ne kadarı kullanılıyor.
    var fraction: Double { maxFactor > 1 ? (factor - 1) / (maxFactor - 1) : 0 }

    func set(_ value: Double) {
        let f = min(maxFactor, max(1, (value * 100).rounded() / 100))
        if f != factor { factor = f }
        if f > 1.001 { start() }
    }

    private func start() {
        guard window == nil, let s = screen,
              let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return }
        // Değiştirmeden önce ekranın kendi gama tablosunu sakla.
        var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, 256, &r, &g, &b, &count) == .success, count > 1 else { return }
        displayID = id
        baseR = Array(r.prefix(Int(count))); baseG = Array(g.prefix(Int(count))); baseB = Array(b.prefix(Int(count)))
        rendered = 1
        applied = 1

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

        if !observing {
            observing = true
            NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                                   name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
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
        let headroom = Double(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1)
        let value = max(1, min(rendered, headroom))
        if abs(value - applied) > 0.002 { apply(value) }

        if factor <= 1.001, rendered <= 1.001 { stop() }
    }

    private func apply(_ value: Double) {
        guard !baseR.isEmpty else { return }
        let f = CGGammaValue(value)
        var r = baseR.map { $0 * f }, g = baseG.map { $0 * f }, b = baseB.map { $0 * f }
        CGSetDisplayTransferByTable(displayID, UInt32(r.count), &r, &g, &b)
        applied = value
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        if applied != 1 || !baseR.isEmpty { restore() }
        window?.orderOut(nil)
        window = nil
        rendered = 1
    }

    /// Ekranın gama tablosunu ilk haline döndürür.
    func restore() {
        guard !baseR.isEmpty else { return }
        var r = baseR, g = baseG, b = baseB
        CGSetDisplayTransferByTable(displayID, UInt32(r.count), &r, &g, &b)
        applied = 1
        baseR = []; baseG = []; baseB = []
    }

    @objc private func screensChanged() {
        guard window != nil else { return }
        if let s = screen {
            window?.setFrame(NSRect(x: s.frame.midX - 1, y: s.frame.maxY - 3, width: 2, height: 2), display: true)
            // Ekran yeniden yapılandırılınca sistem gama tablosunu sıfırlar; yeniden uygula.
            applied = 1
        } else {
            factor = 1
            stop()
        }
    }
}
