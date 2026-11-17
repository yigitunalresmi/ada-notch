import AppKit
import EventKit
import Foundation

/// Asistanın Mac üzerinde kullanabildiği araçlar.
enum ToolBox {

    // MARK: Tanımlar

    private static func tool(_ name: String, _ desc: String, _ props: [String: Any] = [:], required: [String] = []) -> [String: Any] {
        [
            "name": name,
            "description": desc,
            "input_schema": ["type": "object", "properties": props, "required": required] as [String: Any],
        ]
    }

    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func num(_ d: String) -> [String: Any] { ["type": "number", "description": d] }
    private static func bool(_ d: String) -> [String: Any] { ["type": "boolean", "description": d] }
    private static func choice(_ d: String, _ values: [String]) -> [String: Any] {
        ["type": "string", "description": d, "enum": values]
    }

    static func definitions() -> [[String: Any]] {
        let p = Prefs.shared
        var t: [[String: Any]] = [
            tool("get_calendar_events", "List the user's upcoming calendar events.",
                 ["days": num("How many days ahead to look, starting today. Default 3.")]),
            tool("create_calendar_event", "Create an event in the user's default calendar.",
                 ["title": str("Event title"),
                  "start": str("Local start time, format yyyy-MM-dd'T'HH:mm"),
                  "end": str("Local end time, same format. Defaults to one hour after start."),
                  "notes": str("Optional notes")],
                 required: ["title", "start"]),
            tool("get_reminders", "List the user's incomplete reminders."),
            tool("create_reminder", "Create a reminder in the default list.",
                 ["title": str("Reminder text"), "due": str("Optional local due time, format yyyy-MM-dd'T'HH:mm")],
                 required: ["title"]),
            tool("complete_reminder", "Mark the first incomplete reminder whose title contains the given text as done.",
                 ["title": str("Text to match in the reminder title")], required: ["title"]),
            tool("music_control", "Control Spotify or Apple Music, or report what is playing.",
                 ["action": choice("What to do", ["play", "pause", "toggle", "next", "previous", "now_playing"])],
                 required: ["action"]),
            tool("set_volume", "Set the Mac's output volume, or mute/unmute it.",
                 ["percent": num("Volume from 0 to 100"), "muted": bool("Set true to mute, false to unmute")]),
            tool("set_brightness", "Set the built-in display brightness. Values above 100 (up to 160) use the XDR display's extra HDR brightness when Ada's xdr module is on.",
                 ["percent": num("Brightness from 0 to 160")], required: ["percent"]),
            tool("set_appearance", "Switch macOS between dark and light appearance.",
                 ["mode": choice("Target appearance", ["dark", "light", "toggle"])], required: ["mode"]),
            tool("open_app", "Open (or bring forward) an application by name.",
                 ["name": str("Application name, e.g. Safari, Notlar, Spotify")], required: ["name"]),
            tool("quit_app", "Quit a running application by name.",
                 ["name": str("Application name")], required: ["name"]),
            tool("open_url", "Open a URL in the default browser or the app that handles its scheme (https, mailto, spotify, …).",
                 ["url": str("The URL to open")], required: ["url"]),
            tool("get_weather", "Get the current weather at the user's location."),
            tool("timer", "Start, stop or check Ada's countdown timer.",
                 ["action": choice("What to do", ["start", "stop", "status"]),
                  "minutes": num("Duration in minutes when starting"),
                  "label": str("Optional short label shown when the timer ends")],
                 required: ["action"]),
            tool("clipboard", "Read the clipboard or put text on it.",
                 ["action": choice("What to do", ["read", "write"]), "text": str("Text to write")],
                 required: ["action"]),
            tool("note", "Read or edit the user's quick note in Ada.",
                 ["action": choice("What to do", ["read", "append", "replace"]), "text": str("Text to append or the new content")],
                 required: ["action"]),
            tool("get_system_status", "Battery, CPU, memory, volume, brightness, Wi‑Fi state, frontmost app and running apps."),
            tool("set_module", "Turn one of Ada's own features on or off.",
                 ["module": choice("Feature id", ModuleID.allCases.map(\.rawValue)),
                  "enabled": bool("true to turn on, false to turn off")],
                 required: ["module", "enabled"]),
            tool("set_wifi", "Turn the Mac's Wi‑Fi on or off.", ["on": bool("true for on")], required: ["on"]),
            tool("system_action", "Put the display to sleep or start the screen saver.",
                 ["action": choice("What to do", ["sleep_display", "screensaver"])], required: ["action"]),
            tool("list_shortcuts", "List the user's Shortcuts by name."),
            tool("run_shortcut", "Run one of the user's Shortcuts by exact name. The user is asked to approve first.",
                 ["name": str("Shortcut name"), "input": str("Optional text input")], required: ["name"]),
        ]
        t += [
            tool("arrange_window", "Move and resize the frontmost app's focused window on the screen. Needs Ada's Accessibility permission.",
                 ["position": choice("Where to put it", ["left", "right", "top", "bottom", "top_left", "top_right", "bottom_left", "bottom_right", "center", "maximize"])],
                 required: ["position"]),
            tool("get_selected_text", "Read the text currently selected in the frontmost app, e.g. to summarise, translate or rewrite it. Needs Ada's Accessibility permission."),
            tool("find_files", "Search the user's files by name with Spotlight. Returns up to 25 paths.",
                 ["query": str("Part of the file name")], required: ["query"]),
            tool("open_file", "Open a file or folder, or reveal it in Finder.",
                 ["path": str("Absolute path; ~ is allowed"), "reveal": bool("true to show it in Finder instead of opening it")],
                 required: ["path"]),
            tool("add_to_shelf", "Put a file on Ada's file shelf so the user can drag it somewhere or AirDrop it.",
                 ["path": str("Absolute path; ~ is allowed")], required: ["path"]),
            tool("display_tuning", "Adjust the display's colour: warmth (night filter), contrast and extra dimming below minimum brightness. Omitted values stay as they are.",
                 ["warmth": num("0 to 100; 0 is neutral"), "contrast": num("-30 to 40; 0 is neutral"), "dim": num("0 to 70; extra dimming percent")]),
            tool("set_theme", "Change Ada's notch theme.",
                 ["theme": choice("Theme", ["aurora", "neon", "gradient", "glass", "black"])], required: ["theme"]),
            tool("market_prices", "Current price and 24h change for crypto pairs from Binance's public data.",
                 ["symbols": str("Comma-separated Binance symbols such as BTCUSDT, ETHUSDT. Defaults to the user's watchlist.")]),
            tool("audio_output", "List the Mac's audio output devices or switch the output to one of them (speakers, AirPods, a display…).",
                 ["action": choice("What to do", ["list", "set"]), "name": str("Device name, or part of it, when setting")],
                 required: ["action"]),
            tool("pomodoro", "Start or stop a repeating focus/break (Pomodoro) cycle using the durations from Ada's settings.",
                 ["action": choice("What to do", ["start", "stop"])], required: ["action"]),
            tool("keep_awake", "Prevent the Mac and display from sleeping, or allow sleep again.",
                 ["on": bool("true to keep awake")], required: ["on"]),
            tool("remember", "Save a short fact or preference about the user so you know it in future conversations. Use when the user asks you to remember something.",
                 ["fact": str("One self-contained sentence")], required: ["fact"]),
            tool("forget", "Delete saved memories that contain the given text.",
                 ["text": str("Text to match")], required: ["text"]),
        ]
        if p.allowScreen {
            t.append(tool("look_at_screen", "Take a screenshot of the main display and look at it. Use when the user asks about what is on their screen."))
        }
        if p.allowAppleScript {
            t.append(tool("run_applescript", "Run an AppleScript on this Mac for tasks no other tool covers. The user sees the script and must approve it before it runs.",
                          ["script": str("AppleScript source"), "purpose": str("One short sentence, in the user's language, saying what the script does")],
                          required: ["script", "purpose"]))
        }
        if p.allowWeb {
            t.append(["type": "web_search_20260209", "name": "web_search", "max_uses": 3])
        }
        return t
    }

    static func label(_ name: String) -> String {
        switch name {
        case "get_calendar_events": return L("Takvime bakılıyor")
        case "create_calendar_event": return L("Etkinlik ekleniyor")
        case "get_reminders": return L("Anımsatıcılara bakılıyor")
        case "create_reminder": return L("Anımsatıcı ekleniyor")
        case "complete_reminder": return L("Anımsatıcı tamamlanıyor")
        case "music_control": return L("Müzik kontrol ediliyor")
        case "set_volume": return L("Ses ayarlanıyor")
        case "set_brightness": return L("Parlaklık ayarlanıyor")
        case "set_appearance": return L("Görünüm değiştiriliyor")
        case "open_app": return L("Uygulama açılıyor")
        case "quit_app": return L("Uygulama kapatılıyor")
        case "open_url": return L("Bağlantı açılıyor")
        case "get_weather": return L("Hava durumuna bakılıyor")
        case "timer": return L("Zamanlayıcı")
        case "clipboard": return L("Pano")
        case "note": return L("Not")
        case "get_system_status": return L("Sistem durumuna bakılıyor")
        case "set_module": return L("Ada ayarı değiştiriliyor")
        case "set_wifi": return L("Wi‑Fi ayarlanıyor")
        case "system_action": return L("Sistem işlemi")
        case "list_shortcuts": return L("Kestirmeler listeleniyor")
        case "run_shortcut": return L("Kestirme çalıştırılıyor")
        case "look_at_screen": return L("Ekrana bakılıyor")
        case "arrange_window": return L("Pencere yerleştiriliyor")
        case "get_selected_text": return L("Seçili metin okunuyor")
        case "find_files": return L("Dosya aranıyor")
        case "open_file": return L("Dosya açılıyor")
        case "add_to_shelf": return L("Rafa ekleniyor")
        case "keep_awake": return L("Uyku ayarı")
        case "audio_output": return L("Ses çıkışı")
        case "market_prices": return L("Fiyatlara bakılıyor")
        case "display_tuning": return L("Ekran ayarlanıyor")
        case "set_theme": return L("Tema değiştiriliyor")
        case "pomodoro": return "Pomodoro"
        case "remember": return L("Hafızaya kaydediliyor")
        case "forget": return L("Hafızadan siliniyor")
        case "run_applescript": return "AppleScript"
        default: return name
        }
    }

    // MARK: Yardımcılar

    private static func shell(_ path: String, _ args: [String], timeout: TimeInterval = 20) async -> (code: Int32, out: String) {
        await Task.detached { Shell.run(path, args, timeout: timeout) }.value
    }

    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return ISO8601DateFormatter().date(from: s)
    }

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm (EEE)"
        return f.string(from: d)
    }

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private static func wifiDevice() async -> String? {
        let out = await shell("/usr/sbin/networksetup", ["-listallhardwareports"]).out
        let lines = out.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains("Wi-Fi") || line.contains("AirPort") {
            if i + 1 < lines.count, let dev = lines[i + 1].components(separatedBy: ": ").last { return dev }
        }
        return nil
    }

    // MARK: Çalıştırma

    @MainActor
    static func run(_ name: String, _ input: [String: Any]) async -> ToolOutput {
        let agenda = AgendaService.shared
        switch name {

        case "get_calendar_events":
            if !agenda.canReadEvents { _ = try? await agenda.store.requestFullAccessToEvents() }
            guard agenda.canReadEvents else { return .fail("Calendar access is not granted. The user can enable it in System Settings › Privacy & Security › Calendars.") }
            let days = Int(number(input["days"]) ?? 3)
            let events = agenda.fetchEvents(days: days)
            if events.isEmpty { return .ok("No events in the next \(days) day(s).") }
            return .ok(events.prefix(40).map { e in
                e.allDay ? "\(fmt(e.start)) all day — \(e.title)" : "\(fmt(e.start)) → \(fmt(e.end)) — \(e.title)"
            }.joined(separator: "\n"))

        case "create_calendar_event":
            if !agenda.canReadEvents { _ = try? await agenda.store.requestFullAccessToEvents() }
            guard agenda.canReadEvents else { return .fail("Calendar access is not granted.") }
            guard let title = input["title"] as? String, let s = input["start"] as? String, let start = parseDate(s) else {
                return .fail("Missing title, or start is not in yyyy-MM-dd'T'HH:mm format.")
            }
            let end = (input["end"] as? String).flatMap(parseDate)
            do {
                try agenda.createEvent(title: title, start: start, end: end, notes: input["notes"] as? String)
                return .ok("Created \"\(title)\" at \(fmt(start)).")
            } catch { return .fail("Could not save the event: \(error.localizedDescription)") }

        case "get_reminders":
            if !agenda.canReadReminders { _ = try? await agenda.store.requestFullAccessToReminders() }
            guard agenda.canReadReminders else { return .fail("Reminders access is not granted. The user can enable it in System Settings › Privacy & Security › Reminders.") }
            let list = await agenda.fetchReminders()
            if list.isEmpty { return .ok("No incomplete reminders.") }
            return .ok(list.prefix(50).map { r in r.due.map { "\(r.title) (due \(fmt($0)))" } ?? r.title }.joined(separator: "\n"))

        case "create_reminder":
            if !agenda.canReadReminders { _ = try? await agenda.store.requestFullAccessToReminders() }
            guard agenda.canReadReminders else { return .fail("Reminders access is not granted.") }
            guard let title = input["title"] as? String else { return .fail("Missing title.") }
            let due = (input["due"] as? String).flatMap(parseDate)
            do {
                try agenda.createReminder(title: title, due: due)
                return .ok("Reminder created: \(title)" + (due.map { " (due \(fmt($0)))" } ?? ""))
            } catch { return .fail("Could not save the reminder: \(error.localizedDescription)") }

        case "complete_reminder":
            guard agenda.canReadReminders else { return .fail("Reminders access is not granted.") }
            guard let title = input["title"] as? String else { return .fail("Missing title.") }
            if let done = await agenda.completeReminder(matching: title) { return .ok("Completed: \(done)") }
            return .fail("No incomplete reminder matches \"\(title)\".")

        case "music_control":
            let m = MusicService.shared
            let action = input["action"] as? String ?? ""
            if action == "now_playing" {
                guard m.hasTrack else { return .ok("Nothing is playing (Spotify and Music are idle or closed).") }
                return .ok("\(m.isPlaying ? "Playing" : "Paused"): \(m.title) — \(m.artist) (\(m.album)), in \(m.player?.name ?? "?"), \(formatClock(m.livePosition)) / \(formatClock(m.duration))")
            }
            let cmd: String
            switch action {
            case "play": cmd = "play"
            case "pause": cmd = "pause"
            case "toggle": cmd = "playpause"
            case "next": cmd = "next track"
            case "previous": cmd = "previous track"
            default: return .fail("Unknown action.")
            }
            guard m.command(cmd) else { return .fail("Neither Spotify nor Music is running. Open one with open_app first.") }
            try? await Task.sleep(nanoseconds: 900_000_000)
            return .ok("Sent \"\(action)\". Now: \(m.hasTrack ? "\(m.title) — \(m.artist)" : "no track info yet").")

        case "set_volume":
            var done: [String] = []
            if let muted = input["muted"] as? Bool { Audio.setMuted(muted); done.append(muted ? "muted" : "unmuted") }
            if let pct = number(input["percent"]) {
                guard Audio.setVolume(Float(pct / 100)) else { return .fail("The current output device does not allow setting volume.") }
                done.append("volume \(Int(pct))%")
            }
            return done.isEmpty ? .fail("Give percent or muted.") : .ok("Done: " + done.joined(separator: ", "))

        case "set_brightness":
            guard let pct = number(input["percent"]) else { return .fail("Missing percent.") }
            let boost = BoostService.shared
            guard Brightness.set(Float(min(pct, 100) / 100)) else { return .fail("Brightness control is not available on this display.") }
            if pct > 100 {
                guard Prefs.shared.isOn(.xdr), boost.available else {
                    boost.set(1)
                    return .ok("Brightness set to 100%. Extra HDR brightness is unavailable (xdr module off or display unsupported).")
                }
                boost.set(pct / 100)
                return .ok("Brightness set to \(Int((boost.factor * 100).rounded()))% using extra HDR brightness.")
            }
            boost.set(1)
            return .ok("Brightness set to \(Int(pct))%.")

        case "set_appearance":
            let mode = input["mode"] as? String ?? "toggle"
            let value = mode == "dark" ? "true" : (mode == "light" ? "false" : "not dark mode")
            let r = await Script.run("tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)")
            if let err = r.err { return .fail("Could not change appearance: \(err). The user may need to allow Ada to control System Events in System Settings › Privacy & Security › Automation.") }
            return .ok("Appearance set (\(mode)).")

        case "open_app":
            guard let n = input["name"] as? String else { return .fail("Missing name.") }
            let r = await shell("/usr/bin/open", ["-a", n])
            return r.code == 0 ? .ok("Opened \(n).") : .fail("Could not open \"\(n)\": \(r.out)")

        case "quit_app":
            guard let n = input["name"] as? String else { return .fail("Missing name.") }
            let apps = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && ($0.localizedName ?? "").localizedCaseInsensitiveCompare(n) == .orderedSame
            }
            guard !apps.isEmpty else { return .fail("\"\(n)\" is not running.") }
            apps.forEach { $0.terminate() }
            return .ok("Asked \(n) to quit.")

        case "open_url":
            guard let s = input["url"] as? String, let url = URL(string: s), let scheme = url.scheme?.lowercased(),
                  scheme != "file", scheme != "javascript" else { return .fail("Invalid or unsupported URL.") }
            return NSWorkspace.shared.open(url) ? .ok("Opened \(s).") : .fail("Nothing on this Mac can open that URL.")

        case "get_weather":
            guard Prefs.shared.isOn(.weather) else { return .fail("The weather module is off. It can be turned on with set_module.") }
            guard let w = WeatherService.shared.current else { return .fail("Weather is not available yet (location permission may be missing).") }
            var s = "\(w.place.isEmpty ? "Current location" : w.place): \(Int(w.temperature.rounded()))°C, \(w.summary)"
            if let h = w.high, let l = w.low { s += ", high \(Int(h.rounded()))° low \(Int(l.rounded()))°" }
            return .ok(s)

        case "timer":
            let c = CountdownService.shared
            switch input["action"] as? String ?? "" {
            case "start":
                guard let m = number(input["minutes"]), m > 0 else { return .fail("Missing minutes.") }
                c.start(minutes: m, label: input["label"] as? String ?? "")
                return .ok("Timer started for \(m) minute(s).")
            case "stop":
                c.stop()
                return .ok("Timer stopped.")
            default:
                return .ok(c.running ? "Timer running, \(formatClock(c.remaining)) left." : "No timer running.")
            }

        case "clipboard":
            if input["action"] as? String == "write" {
                guard let text = input["text"] as? String else { return .fail("Missing text.") }
                ClipboardService.shared.copy(text)
                return .ok("Copied to clipboard.")
            }
            let s = NSPasteboard.general.string(forType: .string) ?? ""
            return .ok(s.isEmpty ? "The clipboard has no text." : String(s.prefix(8000)))

        case "note":
            let notes = NotesService.shared
            let text = input["text"] as? String ?? ""
            switch input["action"] as? String ?? "read" {
            case "append":
                notes.text += (notes.text.isEmpty ? "" : "\n") + text
                return .ok("Appended to the note.")
            case "replace":
                notes.text = text
                return .ok("Note replaced.")
            default:
                return .ok(notes.text.isEmpty ? "The note is empty." : notes.text)
            }

        case "get_system_status":
            let b = BatteryService.shared, st = StatsService.shared
            st.sample()
            var lines: [String] = []
            if let level = b.level { lines.append("Battery: \(level)%\(b.onAC ? " (on power)" : "")") }
            lines.append(String(format: "CPU: %.0f%%, memory: %.1f of %.0f GB used", st.cpu * 100, st.memUsed / 1_073_741_824, st.memTotal / 1_073_741_824))
            if let v = Audio.volume() { lines.append("Volume: \(Int(v * 100))%\(Audio.muted() ? " (muted)" : "")") }
            if let br = Brightness.get() { lines.append("Brightness: \(Int(br * 100))%") }
            if let dev = await wifiDevice() {
                let w = await shell("/usr/sbin/networksetup", ["-getairportpower", dev]).out
                lines.append("Wi‑Fi: \(w.hasSuffix("On") ? "on" : "off")")
            }
            let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            lines.append("Appearance: \(dark ? "dark" : "light")")
            lines.append("Frontmost app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
            lines.append("Running apps: \(apps.joined(separator: ", "))")
            let on = ModuleID.allCases.filter { Prefs.shared.isOn($0) }.map(\.rawValue)
            lines.append("Ada modules on: \(on.joined(separator: ", "))")
            return .ok(lines.joined(separator: "\n"))

        case "set_module":
            guard let id = input["module"] as? String, let m = ModuleID(rawValue: id), let on = input["enabled"] as? Bool else {
                return .fail("Unknown module or missing enabled.")
            }
            if m == .assistant, !on { return .fail("The assistant can only be turned off from Ada's settings window.") }
            Prefs.shared.set(m, on)
            return .ok("\(m.title) is now \(on ? "on" : "off").")

        case "set_wifi":
            guard let on = input["on"] as? Bool else { return .fail("Missing on.") }
            guard let dev = await wifiDevice() else { return .fail("No Wi‑Fi interface found.") }
            let r = await shell("/usr/sbin/networksetup", ["-setairportpower", dev, on ? "on" : "off"])
            return r.code == 0 && r.out.isEmpty ? .ok("Wi‑Fi turned \(on ? "on" : "off").") : .fail("Could not change Wi‑Fi: \(r.out)")

        case "system_action":
            if input["action"] as? String == "screensaver" {
                let r = await shell("/usr/bin/open", ["-a", "ScreenSaverEngine"])
                return r.code == 0 ? .ok("Screen saver started.") : .fail(r.out)
            }
            let r = await shell("/usr/bin/pmset", ["displaysleepnow"])
            return r.code == 0 ? .ok("Display is going to sleep.") : .fail(r.out)

        case "list_shortcuts":
            let r = await shell("/usr/bin/shortcuts", ["list"])
            return r.code == 0 ? .ok(r.out.isEmpty ? "No shortcuts." : String(r.out.prefix(6000))) : .fail(r.out)

        case "run_shortcut":
            guard let n = input["name"] as? String else { return .fail("Missing name.") }
            guard await AssistantEngine.shared.confirm(title: L("Kestirme çalıştırılsın mı?"), detail: n) else {
                return .fail("The user declined to run this shortcut.")
            }
            var args = ["run", n]
            var tmp: URL?
            if let text = input["input"] as? String, !text.isEmpty {
                let u = FileManager.default.temporaryDirectory.appendingPathComponent("ada-shortcut-\(UUID().uuidString).txt")
                try? text.write(to: u, atomically: true, encoding: .utf8)
                args += ["-i", u.path]
                tmp = u
            }
            let r = await shell("/usr/bin/shortcuts", args, timeout: 90)
            if let tmp { try? FileManager.default.removeItem(at: tmp) }
            return r.code == 0 ? .ok(r.out.isEmpty ? "Shortcut ran." : String(r.out.prefix(6000))) : .fail("Shortcut failed: \(r.out)")

        case "arrange_window":
            if let err = AX.arrange(input["position"] as? String ?? "maximize") { return .fail(err) }
            return .ok("Window arranged.")

        case "get_selected_text":
            guard AX.trusted else { return .fail("Accessibility permission is not granted to Ada (System Settings › Privacy & Security › Accessibility).") }
            guard let text = AX.selectedText(), !text.isEmpty else { return .fail("Nothing is selected, or the frontmost app does not expose its selection.") }
            return .ok(String(text.prefix(20000)))

        case "find_files":
            guard let q = input["query"] as? String, !q.isEmpty else { return .fail("Missing query.") }
            let r = await shell("/usr/bin/mdfind", ["-onlyin", NSHomeDirectory(), "-name", q])
            let lines = r.out.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.contains("/Library/") }
            return .ok(lines.isEmpty ? "No files found." : lines.prefix(25).joined(separator: "\n"))

        case "open_file", "add_to_shelf":
            guard let raw = input["path"] as? String else { return .fail("Missing path.") }
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return .fail("No such file: \(url.path)") }
            if name == "add_to_shelf" {
                if !ShelfService.shared.items.contains(url) { ShelfService.shared.items.append(url) }
                return .ok("Added to the shelf.")
            }
            if input["reveal"] as? Bool == true {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return .ok("Revealed in Finder.")
            }
            return NSWorkspace.shared.open(url) ? .ok("Opened.") : .fail("Could not open the file.")

        case "display_tuning":
            let p = Prefs.shared
            if let w = number(input["warmth"]) { p.warmth = min(1, max(0, w / 100)) }
            if let c = number(input["contrast"]) { p.contrast = min(0.4, max(-0.3, c / 100)) }
            if let d = number(input["dim"]) { p.dim = min(0.7, max(0, d / 100)) }
            return .ok(String(format: "Display: warmth %.0f%%, contrast %+.0f, extra dim %.0f%%.", p.warmth * 100, p.contrast * 100, p.dim * 100))

        case "set_theme":
            guard let t = input["theme"] as? String, Prefs.themes.contains(where: { $0.id == t }) else { return .fail("Unknown theme.") }
            Prefs.shared.theme = t
            return .ok("Theme set to \(t).")

        case "market_prices":
            let raw = (input["symbols"] as? String) ?? Prefs.shared.tickerSymbols
            let symbols = raw.uppercased().components(separatedBy: CharacterSet(charactersIn: ", ;")).filter { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber } }
            guard !symbols.isEmpty else { return .fail("No symbols given.") }
            var comps = URLComponents(string: "https://api.binance.com/api/v3/ticker/24hr")!
            comps.queryItems = [URLQueryItem(name: "symbols", value: "[" + symbols.map { "\"\($0)\"" }.joined(separator: ",") + "]")]
            guard let url = comps.url, let (data, _) = try? await URLSession.shared.data(from: url),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .fail("Could not fetch prices (unknown symbol or no connection).")
            }
            return .ok(arr.map { "\($0["symbol"] ?? "?"): \($0["lastPrice"] ?? "?") (24h \($0["priceChangePercent"] ?? "?")%)" }.joined(separator: "\n"))

        case "audio_output":
            let devices = Audio.outputDevices()
            let current = Audio.defaultDevice()
            if input["action"] as? String == "set" {
                guard let n = input["name"] as? String,
                      let dev = devices.first(where: { $0.name.localizedCaseInsensitiveContains(n) }) else {
                    return .fail("No output device matches. Available: " + devices.map(\.name).joined(separator: ", "))
                }
                return Audio.setDefaultDevice(dev.id) ? .ok("Output switched to \(dev.name).") : .fail("Could not switch the output device.")
            }
            return .ok(devices.map { $0.id == current ? "\($0.name) (current)" : $0.name }.joined(separator: "\n"))

        case "pomodoro":
            if input["action"] as? String == "stop" {
                CountdownService.shared.stop()
                return .ok("Pomodoro stopped.")
            }
            CountdownService.shared.startPomodoro()
            return .ok("Pomodoro started: \(Int(Prefs.shared.pomodoroWork)) min focus, \(Int(Prefs.shared.pomodoroBreak)) min break, repeating.")

        case "keep_awake":
            guard let on = input["on"] as? Bool else { return .fail("Missing on.") }
            KeepAwakeService.shared.set(on)
            return .ok(KeepAwakeService.shared.active ? "The Mac will stay awake until this is turned off or Ada quits." : "Normal sleep behaviour restored.")

        case "remember":
            guard let fact = (input["fact"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !fact.isEmpty else { return .fail("Missing fact.") }
            if !Prefs.shared.memory.contains(fact) { Prefs.shared.memory.append(fact) }
            return .ok("Saved.")

        case "forget":
            guard let text = input["text"] as? String, !text.isEmpty else { return .fail("Missing text.") }
            let before = Prefs.shared.memory.count
            Prefs.shared.memory.removeAll { $0.localizedCaseInsensitiveContains(text) }
            let n = before - Prefs.shared.memory.count
            return n > 0 ? .ok("Removed \(n) memory item(s).") : .fail("No saved memory contains that text.")

        case "look_at_screen":
            guard Prefs.shared.allowScreen else { return .fail("Screen viewing is turned off in Ada's settings.") }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("ada-screen-\(UUID().uuidString).jpg").path
            // Çentik paneli görüntüye girmesin diye önce kapat.
            let wasExpanded = NotchModel.shared.expanded
            NotchModel.shared.expanded = false
            try? await Task.sleep(nanoseconds: 450_000_000)
            let r = await shell("/usr/sbin/screencapture", ["-x", "-m", "-t", "jpg", path])
            if wasExpanded { NotchModel.shared.expanded = true }
            defer { try? FileManager.default.removeItem(atPath: path) }
            guard r.code == 0, let img = NSImage(contentsOfFile: path), let b64 = jpegBase64(img, maxWidth: 1568) else {
                return .fail("Could not capture the screen. The user may need to allow Ada in System Settings › Privacy & Security › Screen & System Audio Recording.")
            }
            return ToolOutput(content: [
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
                ["type": "text", "text": "Screenshot of the main display."],
            ] as [[String: Any]])

        case "run_applescript":
            guard Prefs.shared.allowAppleScript else { return .fail("AppleScript is turned off in Ada's settings.") }
            guard let script = input["script"] as? String else { return .fail("Missing script.") }
            let purpose = input["purpose"] as? String ?? ""
            guard await AssistantEngine.shared.confirm(title: purpose.isEmpty ? L("AppleScript çalıştırılsın mı?") : purpose, detail: script) else {
                return .fail("The user declined to run this script.")
            }
            let r = await Script.run(script)
            if let err = r.err { return .fail("AppleScript error: \(err)") }
            return .ok((r.out ?? "").isEmpty ? "Script ran with no output." : String((r.out ?? "").prefix(6000)))

        default:
            return .fail("Unknown tool: \(name)")
        }
    }

    private static func jpegBase64(_ image: NSImage, maxWidth: CGFloat) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxWidth / CGFloat(cg.width))
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: out)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])?.base64EncodedString()
    }
}
