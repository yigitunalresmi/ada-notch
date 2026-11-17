import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotchController.shared.show()
        ModuleManager.shared.start()

        HotKey.shared.setEnabled(Prefs.shared.hotkey)
        Prefs.shared.$hotkey.dropFirst().sink { HotKey.shared.setEnabled($0) }.store(in: &bag)
        HotKey.shared.setSelectionEnabled(Prefs.shared.selectionHotkey)
        Prefs.shared.$selectionHotkey.dropFirst().sink { HotKey.shared.setSelectionEnabled($0) }.store(in: &bag)

        installMainMenu()
        if ProcessInfo.processInfo.environment["ADA_TEST_CONFETTI"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NotchModel.shared.celebration += 1 }
        }
        // İlk açılışta ayarlar penceresini göster (API anahtarı ve modüller için).
        if !UserDefaults.standard.bool(forKey: "firstRunDone") {
            UserDefaults.standard.set(true, forKey: "firstRunDone")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.openSettings() }
        }
        if let t = ProcessInfo.processInfo.environment["ADA_TEST_BOOST"].flatMap(Double.init) {
            // Geliştirme testi: parlaklığı geçici olarak %100 yapıp katmanı açar, 4 sn sonra eski haline döner.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let old = Brightness.get()
                _ = Brightness.set(1)
                BoostService.shared.set(t)
                let s = NSScreen.main
                print("boost factor=\(BoostService.shared.factor) available=\(BoostService.shared.available) potential=\(s?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 0)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    print("headroom now=\(s?.maximumExtendedDynamicRangeColorComponentValue ?? 0)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    BoostService.shared.set(1)
                    if let old { _ = Brightness.set(old) }
                }
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Ada")
        let menu = NSMenu()
        menu.addItem(withTitle: L("Asistanı Aç  (⌥ Boşluk)"), action: #selector(openAssistant), keyEquivalent: "")
        menu.addItem(withTitle: L("Ayarlar…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Ada'dan Çık"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    /// Menü çubuğunda görünmese de, metin alanlarında ⌘V/⌘C/⌘X/⌘A/⌘Z'nin çalışması için gerekli.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Ada'dan Çık"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("Düzen"))
        edit.addItem(withTitle: L("Geri Al"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L("Yinele"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Kes"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Kopyala"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Yapıştır"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Tümünü Seç"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: L("Pencere"))
        window.addItem(withTitle: L("Kapat"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ekstra parlaklık açıksa ekranı normal haline döndür.
        BoostService.shared.restore()
    }

    @objc func openAssistant() { NotchController.shared.toggleAssistant() }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = L("Ada Ayarları")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            settingsWindow = w
        }
        NotchController.shared.close()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quit() { NSApp.terminate(nil) }

    static func showSettings() {
        (NSApp.delegate as? AppDelegate)?.openSettings()
    }
}
