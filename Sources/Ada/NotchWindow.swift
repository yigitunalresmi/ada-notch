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
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func screensChanged() { reposition() }

    private func reposition() {
        let target = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
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

    private func tick() {
        guard let s = screen else { return }
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
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
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
    private var ref: EventHotKeyRef?
    private var installed = false

    func setEnabled(_ on: Bool) {
        if on, ref == nil {
            if !installed {
                var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
                InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                    DispatchQueue.main.async { NotchController.shared.toggleAssistant() }
                    return noErr
                }, 1, &spec, nil, nil)
                installed = true
            }
            let id = EventHotKeyID(signature: OSType(0x4144_4131), id: 1)
            RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref)
        } else if !on, let r = ref {
            UnregisterEventHotKey(r)
            ref = nil
        }
    }
}
