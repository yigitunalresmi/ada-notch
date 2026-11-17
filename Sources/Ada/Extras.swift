import AppKit
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Uyanık tut

/// Mac'in ve ekranın uykuya geçmesini engeller (caffeinate). Ada kapanınca kendiliğinden biter.
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()
    @Published private(set) var active = false
    private var process: Process?

    func set(_ on: Bool) {
        if on, process == nil {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-d", "-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
            do {
                try p.run()
                process = p
                active = true
            } catch {
                active = false
            }
        } else if !on, let p = process {
            p.terminate()
            process = nil
            active = false
        }
    }

    func toggle() { set(!active) }
}

// MARK: - Erişilebilirlik yardımcıları (pencere düzeni, seçili metin)

enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    /// Öndeki pencereyi ekranda yerleştirir. Hata varsa açıklamasını döndürür.
    static func arrange(_ position: String) -> String? {
        guard trusted else { return "Accessibility permission is not granted to Ada (System Settings › Privacy & Security › Accessibility)." }
        guard let win = focusedWindow() else { return "The frontmost app has no window that can be moved." }
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let primary = NSScreen.screens.first else { return "No screen." }
        let vf = screen.visibleFrame
        var r = vf
        switch position {
        case "left": r.size.width = vf.width / 2
        case "right": r.size.width = vf.width / 2; r.origin.x = vf.midX
        case "top": r.size.height = vf.height / 2; r.origin.y = vf.midY
        case "bottom": r.size.height = vf.height / 2
        case "top_left": r.size = CGSize(width: vf.width / 2, height: vf.height / 2); r.origin.y = vf.midY
        case "top_right": r.size = CGSize(width: vf.width / 2, height: vf.height / 2); r.origin = CGPoint(x: vf.midX, y: vf.midY)
        case "bottom_left": r.size = CGSize(width: vf.width / 2, height: vf.height / 2)
        case "bottom_right": r.size = CGSize(width: vf.width / 2, height: vf.height / 2); r.origin.x = vf.midX
        case "center":
            r.size = CGSize(width: vf.width * 0.7, height: vf.height * 0.8)
            r.origin = CGPoint(x: vf.midX - r.width / 2, y: vf.midY - r.height / 2)
        default: break // maximize
        }
        // AX koordinatları sol üst köşeden ölçülür.
        var origin = CGPoint(x: r.minX, y: primary.frame.height - r.maxY)
        var size = r.size
        guard let pv = AXValueCreate(.cgPoint, &origin), let sv = AXValueCreate(.cgSize, &size) else { return "Internal error." }
        AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
        let err = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sv)
        AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
        return err == .success ? nil : "The window refused to be resized."
    }

    static func selectedText() -> String? {
        guard trusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
        var text: CFTypeRef?
        guard AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, &text) == .success else { return nil }
        return text as? String
    }
}

// MARK: - Hızlı işlemler

enum QuickAction {
    static func toggleDarkMode() {
        Script.fire("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    }

    static func screenshotSelection() {
        NotchController.shared.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            // Seçilen alan panoya kopyalanır.
            Shell.run("/usr/sbin/screencapture", ["-i", "-c"], timeout: 120)
        }
    }

    static func sleepDisplay() {
        NotchController.shared.close()
        DispatchQueue.global().async { Shell.run("/usr/bin/pmset", ["displaysleepnow"]) }
    }

    private static var sampler: NSColorSampler?

    /// Ekrandan bir renk seçtirir ve onaltılık kodunu panoya kopyalar.
    static func pickColor() {
        NotchController.shared.close()
        let s = NSColorSampler()
        sampler = s
        s.show { color in
            sampler = nil
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                             Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
            ClipboardService.shared.copy(hex)
            NotchModel.shared.showHUD(HUDInfo(icon: "eyedropper.halffull", title: Lf("%@ kopyalandı", "\(hex)"), tint: Color(nsColor: c)), seconds: 2.6)
        }
    }

    static func toggleMute() {
        let muted = !Audio.muted()
        Audio.setMuted(muted)
        HUDService.shared.showVolume(Audio.volume() ?? 0, muted: muted)
    }
}

struct QuickActionsRow: View {
    @ObservedObject var awake = KeepAwakeService.shared
    @State private var muted = Audio.muted()

    var body: some View {
        HStack(spacing: 6) {
            action("moon.fill", L("Görünüm")) { QuickAction.toggleDarkMode() }
            action(awake.active ? "cup.and.saucer.fill" : "cup.and.saucer", L("Uyanık"), on: awake.active) { awake.toggle() }
            action("camera.viewfinder", L("Alıntı")) { QuickAction.screenshotSelection() }
            action(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", L("Sessiz"), on: muted) {
                QuickAction.toggleMute()
                muted = Audio.muted()
            }
            action("eyedropper", L("Renk")) { QuickAction.pickColor() }
            action("display", L("Uyut")) { QuickAction.sleepDisplay() }
            Menu {
                let current = Audio.defaultDevice()
                ForEach(Audio.outputDevices(), id: \.id) { dev in
                    Button { Audio.setDefaultDevice(dev.id) } label: {
                        if dev.id == current { Label(dev.name, systemImage: "checkmark") } else { Text(dev.name) }
                    }
                }
            } label: {
                Label(L("Çıkış"), systemImage: "hifispeaker.fill").labelStyle(.titleAndIcon)
            }
            .menuStyle(.button)
            .buttonStyle(PillButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer(minLength: 0)
        }
        .onAppear { muted = Audio.muted() }
    }

    private func action(_ icon: String, _ title: String, on: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: icon).labelStyle(.titleAndIcon)
        }
        .buttonStyle(PillButtonStyle(tint: on ? Prefs.shared.accentColor.opacity(0.75) : .white.opacity(0.14)))
    }
}

// MARK: - Uygulama başlatıcı

struct LauncherView: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: L("Uygulamalar"))
                Spacer()
                Button { addApp() } label: { Label(L("Ekle"), systemImage: "plus") }.buttonStyle(PillButtonStyle())
            }
            if prefs.pinnedApps.isEmpty {
                EmptyHint(icon: "square.grid.3x3", text: L("Sık kullandığınız uygulamaları \"Ekle\" ile sabitleyin."))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(prefs.pinnedApps, id: \.self) { path in
                            Button {
                                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
                                NotchController.shared.close()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)).resizable().frame(width: 52, height: 52)
                                    Text(FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""))
                                        .font(.system(size: 10)).lineLimit(1).frame(width: 70)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(L("Başlatıcıdan Kaldır")) { prefs.pinnedApps.removeAll { $0 == path } }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func addApp() {
        NotchController.shared.close()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Sabitle")
        if panel.runModal() == .OK {
            for url in panel.urls where !prefs.pinnedApps.contains(url.path) { prefs.pinnedApps.append(url.path) }
        }
    }
}
