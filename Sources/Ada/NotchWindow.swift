import AppKit
import Carbon.HIToolbox
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Pencerenin menü çubuğunun altına itilmesini engelle; çentiğin üstünde durmalı.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Uygulama etkin değilken de ⌘V / ⌘C / ⌘X / ⌘A / ⌘Z çalışsın.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command,
           let ch = event.charactersIgnoringModifiers?.lowercased() {
            let shift = event.modifierFlags.contains(.shift)
            let action: Selector?
            switch ch {
            case "v": action = #selector(NSText.paste(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "x": action = #selector(NSText.cut(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            case "z": action = Selector((shift ? "redo:" : "undo:"))
            default: action = nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        NotchController.shared.close()
    }
}

final class NotchController: NSObject, NSWindowDelegate {
    static let shared = NotchController()

    private var panel: NotchPanel!
    private var timer: Timer?
    private var insideSince: Date?
    private var lastInside = Date.distantPast
    private let model = NotchModel.shared
    private let panelSize = CGSize(width: 920, height: 440)
    private var screen: NSScreen?
    /// Geliştirme için: ADA_HOLD_TAB=home|assistant|tools|shelf|mirror ile çentik açık tutulur.
    private let holdTab = ProcessInfo.processInfo.environment["ADA_HOLD_TAB"].flatMap(NotchTab.init(rawValue:))

    func show() {
        panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // isFloatingPanel düzeyi sıfırladığı için düzey ondan SONRA ayarlanmalı;
        // aksi halde pencere menü çubuğunun altında kalır ve üst satır tıklanamaz.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.ignoresMouseEvents = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: NotchRootView())

        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        if let holdTab { model.expand(tab: holdTab) }
        // Geliştirme testi: ADA_TEST_CLOSE ile çentik açılır ve 4. saniyede kapanır (kapanışı kare kare yakalamak için).
        if ProcessInfo.processInfo.environment["ADA_TEST_CLOSE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.previewUntil = Date().addingTimeInterval(2.5); self.model.expand(tab: .home) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { self.previewUntil = .distantPast; self.close() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            self?.handleScroll(e)
            return e
        }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func screensChanged() { reposition() }

    func screenPrefChanged() {
        guard panel != nil else { return }
        reposition()
    }

    // MARK: Kaydırma hareketleri

    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0
    private var swipeFired = false

    /// İki parmakla kaydırma: üst çubukta sekme değiştirir; kapalı çentikte parça atlar ya da aşağı kaydırınca açar.
    private func handleScroll(_ e: NSEvent) {
        guard Prefs.shared.gestures, e.window === panel, e.hasPreciseScrollingDeltas else { return }
        if e.phase == .began { swipeX = 0; swipeY = 0; swipeFired = false }
        guard e.phase == .changed, !swipeFired else { return }
        swipeX += e.scrollingDeltaX
        swipeY += e.scrollingDeltaY
        let horizontal = abs(swipeX) > 45 && abs(swipeX) > abs(swipeY) * 2
        if model.expanded {
            // Yalnızca üst çubuğun üzerindeyken: içerikteki yatay kaydırmalarla karışmasın.
            let topBar = e.locationInWindow.y > panel.frame.height - max(model.notchSize.height, 30)
            guard horizontal, topBar else { return }
            let tabs = model.availableTabs
            guard let index = tabs.firstIndex(of: model.tab) else { return }
            let next = index + (swipeX < 0 ? 1 : -1)
            if tabs.indices.contains(next) { model.tab = tabs[next] }
            swipeFired = true
        } else if horizontal, model.compactMusic {
            if swipeX < 0 { MusicService.shared.next() } else { MusicService.shared.previous() }
            swipeFired = true
        } else if swipeY > 40, abs(swipeY) > abs(swipeX) * 2 {
            model.expand()
            swipeFired = true
        }
    }

    func attachToLockScreen() {
        guard panel != nil else { return }
        LockScreen.attach(panel)
    }

    private func reposition() {
        let chosen = Prefs.shared.screenName.isEmpty ? nil : NSScreen.screens.first { $0.localizedName == Prefs.shared.screenName }
        let target = chosen ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let s = target else { return }
        screen = s
        if s.safeAreaInsets.top > 0 {
            let left = s.auxiliaryTopLeftArea?.width ?? 0
            let right = s.auxiliaryTopRightArea?.width ?? 0
            let w = s.frame.width - left - right
            model.notchSize = CGSize(width: max(140, w + 12), height: s.safeAreaInsets.top)
        } else {
            let menuBar = s.frame.maxY - s.visibleFrame.maxY
            model.notchSize = CGSize(width: 190, height: max(24, min(menuBar, 32)))
        }
        let origin = CGPoint(x: s.frame.midX - panelSize.width / 2, y: s.frame.maxY - panelSize.height)
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    /// Kullanıcı yazarken ya da konuşurken çentik kendiliğinden kapanmaz.
    private var previewUntil = Date.distantPast

    /// Ayarlar penceresinden: çentiği birkaç saniye açık tutar.
    func preview() {
        previewUntil = Date().addingTimeInterval(6)
        model.expand()
    }

    private var locked: Bool {
        if Date() < previewUntil { return true }
        if holdTab != nil { return true }
        if SpeechService.shared.listening || SpeechService.shared.conversation { return true }
        if model.dropTargeted { return true }
        return panel.isKeyWindow && model.tab == .assistant
    }

    private var fullscreenChecked = Date.distantPast
    private var hiddenForFullscreen = false

    private func tick() {
        guard let s = screen else { return }
        // Tam ekran bir uygulama öndeyken (film, sunum, oyun) Ada görünmez olur.
        if Prefs.shared.hideInFullscreen {
            if Date().timeIntervalSince(fullscreenChecked) > 1 {
                fullscreenChecked = Date()
                hiddenForFullscreen = Fullscreen.active(on: s)
            }
        } else {
            hiddenForFullscreen = false
        }
        if hiddenForFullscreen {
            if panel.alphaValue != 0 {
                panel.alphaValue = 0
                panel.ignoresMouseEvents = true
                model.collapse()
            }
            return
        } else if panel.alphaValue == 0 {
            panel.alphaValue = 1
        }
        let size = model.currentSize()
        let pad: CGFloat = model.expanded ? 14 : 2
        let rect = NSRect(
            x: s.frame.midX - size.width / 2 - pad,
            y: s.frame.maxY - size.height - pad,
            width: size.width + 2 * pad,
            height: size.height + pad + 4)
        let inside = rect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        let now = Date()
        if inside {
            lastInside = now
            if insideSince == nil { insideSince = now }
            if !model.expanded, Prefs.shared.openOnHover,
               let since = insideSince, now.timeIntervalSince(since) >= Prefs.shared.hoverDelay {
                model.expand()
            }
        } else {
            insideSince = nil
            if model.expanded, !locked, now.timeIntervalSince(lastInside) > Prefs.shared.closeDelay {
                close()
            }
        }
    }

    func close() {
        model.collapse()
        // Klavye odağı öndeki uygulamaya geri verilir. Pencereyi hemen gizleyip göstermek kapanış
        // animasyonunu keserdi; bu yüzden animasyon bittikten sonra yapılır.
        guard panel.isKeyWindow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.model.expanded, self.panel.isKeyWindow else { return }
            self.panel.orderOut(nil)
            self.panel.orderFrontRegardless()
        }
    }

    func toggleAssistant() {
        if model.expanded && model.tab == .assistant && panel.isKeyWindow {
            close()
            return
        }
        guard Prefs.shared.isOn(.assistant) else { return }
        model.expand(tab: .assistant)
        lastInside = Date()
        panel.makeKeyAndOrderFront(nil)
        model.focusInput += 1
    }

    /// Öndeki uygulamada seçili metni alıp asistanı hızlı işlemlerle açar.
    func askAboutSelection() {
        guard Prefs.shared.isOn(.assistant) else { return }
        guard AX.trusted else {
            model.showHUD(HUDInfo(icon: "exclamationmark.triangle.fill", title: L("Erişilebilirlik izni gerekli"), tint: .orange), seconds: 2.6)
            return
        }
        guard let text = AX.selectedText()?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            model.showHUD(HUDInfo(icon: "text.cursor", title: L("Seçili metin yok"), tint: .gray), seconds: 2)
            return
        }
        AssistantEngine.shared.selection = String(text.prefix(12000))
        model.expand(tab: .assistant)
        lastInside = Date()
        panel.makeKeyAndOrderFront(nil)
        model.focusInput += 1
    }

    /// ⌥⇧V: panoyu aç.
    func openClipboard() {
        guard Prefs.shared.isOn(.clipboard) else { return }
        if model.expanded, model.tab == .tools { close(); return }
        previewUntil = Date().addingTimeInterval(8)
        model.expand(tab: .tools)
        lastInside = Date()
    }

    func makeKey() {
        panel.makeKey()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Dışarı tıklanınca kapan (fare hâlâ çentiğin üstündeyse açık kalır).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.holdTab == nil, self.model.expanded, self.insideSince == nil else { return }
            if !SpeechService.shared.listening, !SpeechService.shared.conversation { self.model.collapse() }
        }
    }
}

// MARK: - Genel kısayol (⌥ Boşluk)

final class HotKey {
    static let shared = HotKey()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    /// Kimlik → (tuş, niteleyiciler). 1: asistan, 2: seçili metin, 3: pano, 4: mikrofon.
    private let keys: [UInt32: (key: Int, mods: Int)] = [
        1: (kVK_Space, optionKey),
        2: (kVK_Space, optionKey | shiftKey),
        3: (kVK_ANSI_V, optionKey | shiftKey),
        4: (kVK_ANSI_M, optionKey),
    ]

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async {
                switch id {
                case 2: NotchController.shared.askAboutSelection()
                case 3: NotchController.shared.openClipboard()
                case 4: Microphone.toggle()
                default: NotchController.shared.toggleAssistant()
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func set(_ id: UInt32, enabled: Bool) {
        if enabled, refs[id] == nil, let k = keys[id] {
            install()
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(k.key), UInt32(k.mods), EventHotKeyID(signature: OSType(0x4144_4131), id: id), GetApplicationEventTarget(), 0, &ref)
            if let ref { refs[id] = ref }
        } else if !enabled, let ref = refs[id] {
            UnregisterEventHotKey(ref)
            refs[id] = nil
        }
    }

    /// ⌥ Boşluk: asistanı aç.
    func setEnabled(_ on: Bool) { set(1, enabled: on) }

    /// ⌥⇧ Boşluk: seçili metinle asistanı aç.
    func setSelectionEnabled(_ on: Bool) { set(2, enabled: on) }
}
