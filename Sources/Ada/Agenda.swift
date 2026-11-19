import AppKit
import CoreLocation
import EventKit
import SwiftUI

// MARK: - Takvim ve anımsatıcılar

struct AgendaEvent: Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var color: Color
    var url: URL? = nil

    /// "12 dk" / "şimdi"
    var countdown: String {
        let m = Int((start.timeIntervalSinceNow / 60).rounded(.up))
        return m <= 0 ? L("şimdi") : Lf("%@ dk", "\(m)")
    }
}

struct AgendaReminder: Identifiable {
    var id: String
    var title: String
    var due: Date?
}

final class AgendaService: ObservableObject {
    static let shared = AgendaService()
    let store = EKEventStore()

    @Published var events: [AgendaEvent] = []
    @Published var reminders: [AgendaReminder] = []
    /// Bir saat içinde başlayacak ya da yeni başlamış ilk etkinlik.
    @Published var next: AgendaEvent?
    @Published var eventsDenied = false
    @Published var remindersDenied = false

    private var eventsOn = false
    private var remindersOn = false
    private var timer: Timer?
    private var observing = false

    func setEnabled(events: Bool, reminders: Bool) {
        let changed = events != eventsOn || reminders != remindersOn
        eventsOn = events
        remindersOn = reminders
        if !events { self.events = []; self.next = nil }
        if !reminders { self.reminders = [] }
        guard events || reminders else {
            timer?.invalidate(); timer = nil
            return
        }
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .EKEventStoreChanged, object: store)
        }
        if timer == nil {
            let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        if changed { requestAndRefresh() }
    }

    @objc private func storeChanged() { DispatchQueue.main.async { self.refresh() } }

    private func requestAndRefresh() {
        if eventsOn {
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { self.eventsDenied = !granted; self.refresh() }
            }
        }
        if remindersOn {
            store.requestFullAccessToReminders { granted, _ in
                DispatchQueue.main.async { self.remindersDenied = !granted; self.refresh() }
            }
        }
    }

    var canReadEvents: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var canReadReminders: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    func fetchEvents(days: Int) -> [AgendaEvent] {
        guard canReadEvents else { return [] }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: max(1, days), to: Calendar.current.startOfDay(for: now))!
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: end, calendars: nil)
        return store.events(matching: pred)
            .filter { $0.endDate > now && (Opt.flag("calendar.allDay") || !$0.isAllDay) }
            .sorted { $0.startDate < $1.startDate }
            .map {
                AgendaEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? L("(Başlıksız)"),
                            start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay,
                            color: Color(nsColor: $0.calendar.color), url: Self.meetingURL($0))
            }
    }

    private static func meetingURL(_ e: EKEvent) -> URL? {
        if let u = e.url, u.scheme?.hasPrefix("http") == true { return u }
        let text = [e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com", "meet.jit.si"]
        for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let u = m.url, let h = u.host, hosts.contains(where: { h.hasSuffix($0) }) { return u }
        }
        return nil
    }

    func fetchReminders() async -> [AgendaReminder] {
        guard canReadReminders else { return [] }
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { list in
                let items = (list ?? []).map {
                    AgendaReminder(id: $0.calendarItemIdentifier, title: $0.title ?? "",
                                   due: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) })
                }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                cont.resume(returning: items)
            }
        }
    }

    func refresh() {
        if eventsOn {
            events = fetchEvents(days: max(1, Int(Opt.num("calendar.days"))))
            let now = Date()
            next = events.first { !$0.allDay && $0.start > now.addingTimeInterval(-300) && $0.start < now.addingTimeInterval(Opt.num("calendar.lead") * 60) }
        } else {
            next = nil
        }
        if remindersOn {
            Task { @MainActor in self.reminders = await self.fetchReminders() }
        }
    }

    // Asistanın kullandığı yazma işlemleri

    func createEvent(title: String, start: Date, end: Date?, notes: String?) throws {
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = start
        e.endDate = end ?? start.addingTimeInterval(3600)
        e.notes = notes
        e.calendar = store.defaultCalendarForNewEvents
        try store.save(e, span: .thisEvent)
        refresh()
    }

    func createReminder(title: String, due: Date?) throws {
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = store.defaultCalendarForNewReminders()
        if let due {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(r, commit: true)
        refresh()
    }

    func completeReminder(matching text: String) async -> String? {
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let list: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        guard let r = list.first(where: { ($0.title ?? "").localizedCaseInsensitiveContains(text) }) else { return nil }
        r.isCompleted = true
        try? store.save(r, commit: true)
        await MainActor.run { self.refresh() }
        return r.title
    }
}

// MARK: - Hava durumu

struct WeatherNow {
    var temperature: Double
    var code: Int
    var isDay: Bool
    var high: Double?
    var low: Double?
    var place: String

    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var summary: String {
        switch code {
        case 0: return L("Açık")
        case 1: return L("Az bulutlu")
        case 2: return L("Parçalı bulutlu")
        case 3: return L("Kapalı")
        case 45, 48: return L("Sisli")
        case 51...57: return L("Çisenti")
        case 61...67: return L("Yağmurlu")
        case 71...77, 85, 86: return L("Karlı")
        case 80...82: return L("Sağanak")
        case 95...99: return L("Gök gürültülü fırtına")
        default: return L("Bulutlu")
        }
    }
}

final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    @Published var current: WeatherNow?
    @Published var hourly: [HourForecast] = []
    @Published var daily: [DayForecast] = []
    private var lastRainAlert = Date.distantPast
    @Published var denied = false

    private let manager = CLLocationManager()
    private var timer: Timer?
    private var enabled = false
    private var place = ""

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()
            let t = Timer(timeInterval: max(600, Opt.num("weather.refresh") * 60), repeats: true) { [weak self] _ in self?.manager.requestLocation() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate(); timer = nil
            current = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        denied = (s == .denied || s == .restricted)
        if enabled, !denied, s != .notDetermined { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        CLGeocoder().reverseGeocodeLocation(loc) { marks, _ in
            let name = marks?.first?.locality ?? marks?.first?.administrativeArea ?? ""
            DispatchQueue.main.async {
                self.place = name
                if var c = self.current { c.place = name; self.current = c }
            }
        }
        fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
    }

    /// Hava şu an yağışlı değilse ve bir saat içinde yağış olasılığı eşiği aşıyorsa haber verir.
    private func checkRain(_ hours: [HourForecast], currentCode: Int) {
        let threshold = Opt.num("weather.rainAlert")
        guard threshold > 0, let next = hours.first, Double(next.rain) >= threshold, currentCode < 51,
              Date().timeIntervalSince(lastRainAlert) > 3 * 3600 else { return }
        lastRainAlert = Date()
        NotchModel.shared.showHUD(HUDInfo(icon: "cloud.rain.fill", title: Lf("Bir saat içinde yağış olasılığı %%%@", "\(next.rain)"), wide: true, tint: .cyan), seconds: 5)
    }

    private func fetch(lat: Double, lon: Double) {
        // Konum yaklaşık 1 km hassasiyete yuvarlanarak gönderilir.
        let la = String(format: "%.2f", lat), lo = String(format: "%.2f", lon)
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(la)&longitude=\(lo)&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max&hourly=temperature_2m,weather_code,precipitation_probability,is_day&timezone=auto&forecast_days=6"
        guard let url = URL(string: s) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = json["current"] as? [String: Any],
                  let temp = cur["temperature_2m"] as? Double else { return }
            let daily = json["daily"] as? [String: Any]
            let hi = (daily?["temperature_2m_max"] as? [Double])?.first
            let lo = (daily?["temperature_2m_min"] as? [Double])?.first
            var days: [DayForecast] = []
            if let dates = daily?["time"] as? [String], let highs = daily?["temperature_2m_max"] as? [Double],
               let lows = daily?["temperature_2m_min"] as? [Double] {
                let codes = daily?["weather_code"] as? [Int] ?? []
                let rains = daily?["precipitation_probability_max"] as? [Int] ?? []
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "yyyy-MM-dd"
                for i in 0..<min(dates.count, highs.count, lows.count) {
                    guard let d = df.date(from: dates[i]) else { continue }
                    days.append(DayForecast(date: d, high: highs[i], low: lows[i], code: i < codes.count ? codes[i] : 3, rain: i < rains.count ? rains[i] : 0))
                }
            }
            let now = WeatherNow(temperature: temp, code: cur["weather_code"] as? Int ?? 3,
                                 isDay: (cur["is_day"] as? Int ?? 1) == 1, high: hi, low: lo, place: "")
            // Saatlik tahmin: şu andan sonraki saatler
            var hours: [HourForecast] = []
            if let h = json["hourly"] as? [String: Any], let times = h["time"] as? [String],
               let temps = h["temperature_2m"] as? [Double], let codes = h["weather_code"] as? [Int] {
                let rains = h["precipitation_probability"] as? [Int] ?? []
                let days = h["is_day"] as? [Int] ?? []
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd'T'HH:mm"
                let nowDate = Date()
                for i in 0..<min(times.count, temps.count, codes.count) {
                    guard let d = f.date(from: times[i]), d > nowDate else { continue }
                    hours.append(HourForecast(time: d, temperature: temps[i], code: codes[i],
                                              isDay: i < days.count ? days[i] == 1 : true, rain: i < rains.count ? rains[i] : 0))
                    if hours.count >= 8 { break }
                }
            }
            DispatchQueue.main.async {
                var n = now
                n.place = self.place
                self.current = n
                self.hourly = hours
                self.daily = days
                self.checkRain(hours, currentCode: now.code)
            }
        }.resume()
    }
}

// MARK: - Görünüm

struct AgendaColumn: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var agenda = AgendaService.shared
    @ObservedObject var weather = WeatherService.shared
    // ADA_TEST_FORECAST: geliştirme sırasında tahmin şeridini açık başlatır.
    @State private var showForecast = ProcessInfo.processInfo.environment["ADA_TEST_FORECAST"] != nil

    var body: some View {
        let tall = prefs.expandedHeight >= 290
        VStack(alignment: .leading, spacing: tall ? 10 : 7) {
            if prefs.isOn(.weather) {
                weatherRow
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showForecast.toggle() } }
                    .help(L("Saatlik tahmin için tıklayın"))
            }
            if prefs.isOn(.ticker) { TickerRow() }
            if prefs.isOn(.clocks) { ClocksRow() }
            if showForecast, prefs.isOn(.weather) {
                ForecastStrip().transition(.blurReplace)
            }
            if prefs.isOn(.calendar), !showForecast {
                VStack(alignment: .leading, spacing: 5) {
                    SectionTitle(text: L("Yaklaşan"))
                    if agenda.eventsDenied {
                        hint(L("Takvim izni verilmedi"))
                    } else if agenda.events.isEmpty {
                        hint(L("Yaklaşan etkinlik yok"))
                    } else {
                        ForEach(agenda.events.prefix(max(1, Int(Opt.num("calendar.count"))))) { e in
                            HStack(spacing: 7) {
                                Capsule().fill(e.color).frame(width: 3, height: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(when(e)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                                }
                                if let url = e.url {
                                    Spacer(minLength: 4)
                                    Button(L("Katıl")) { NSWorkspace.shared.open(url) }
                                        .buttonStyle(PillButtonStyle(tint: .green.opacity(0.65)))
                                }
                            }
                        }
                    }
                }
            }
            if prefs.isOn(.reminders), !showForecast {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: L("Anımsatıcılar"))
                    if agenda.remindersDenied {
                        hint(L("Anımsatıcı izni verilmedi"))
                    } else if agenda.reminders.isEmpty {
                        hint(L("Bekleyen anımsatıcı yok"))
                    } else {
                        ForEach(agenda.reminders.filter { !Opt.flag("reminders.onlyDue") || $0.due != nil }.prefix(max(1, Int(Opt.num("reminders.count"))))) { r in
                            HStack(spacing: 6) {
                                Image(systemName: "circle").font(.system(size: 10)).foregroundStyle(.orange)
                                Text(r.title).font(.system(size: 12)).lineLimit(1)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
    }

    @ViewBuilder private var weatherRow: some View {
        if let w = weather.current {
            HStack(spacing: 10) {
                Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(prefs.temp(w.temperature))°").font(.system(size: 20, weight: .semibold))
                        Text(w.summary).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    }
                    HStack(spacing: 6) {
                        if !w.place.isEmpty { Text(w.place) }
                        if let h = w.high, let l = w.low { Text("↑\(prefs.temp(h))°  ↓\(prefs.temp(l))°") }
                    }
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
            }
        } else {
            hint(weather.denied ? L("Hava durumu için konum izni verilmedi") : L("Hava durumu yükleniyor…"))
        }
    }

    private func when(_ e: AgendaEvent) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(e.start) { day = L("Bugün") }
        else if cal.isDateInTomorrow(e.start) { day = L("Yarın") }
        else {
            let f = DateFormatter()
            f.locale = appLocale
            f.dateFormat = "EEEE"
            day = f.string(from: e.start)
        }
        if e.allDay { return Lf("%@ · Tüm gün", "\(day)") }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        if e.start <= Date() { return Lf("Şimdi · %@'e kadar", "\(f.string(from: e.end))") }
        return "\(day) · \(f.string(from: e.start))–\(f.string(from: e.end))"
    }
}
