import AVFoundation
import AppKit
import CoreBluetooth
import CoreLocation
import EventKit
import Speech
import SwiftUI

// MARK: - İzinler
//
// Kural: Ada açılışta hiçbir izni kendiliğinden istemez. Servisler yalnızca izin zaten verilmişse çalışır;
// izinler bu sayfadaki düğmelerle, kullanıcı isteyince istenir.

enum PermissionState {
    case granted, denied, notAsked, unknown
}

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility, screen, fullDisk, calendar, reminders, location, bluetooth, camera, microphone, speech
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return L("Erişilebilirlik")
        case .screen: return L("Ekran Kaydı")
        case .fullDisk: return L("Tam Disk Erişimi")
        case .calendar: return L("Takvim")
        case .reminders: return L("Anımsatıcılar")
        case .location: return L("Konum")
        case .bluetooth: return "Bluetooth"
        case .camera: return L("Kamera")
        case .microphone: return L("Mikrofon")
        case .speech: return L("Konuşma Tanıma")
        }
    }

    var icon: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screen: return "rectangle.dashed.badge.record"
        case .fullDisk: return "internaldrive"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .location: return "location.fill"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .speech: return "waveform"
        }
    }

    /// Bu izin ne işe yarıyor.
    var purpose: String {
        switch self {
        case .accessibility: return L("Ses ve parlaklık tuşları göstergesi, pencere yerleştirme, seçili metni okuma, panodan yapıştırma.")
        case .screen: return L("Kilit ekranında görünme, ekran alıntısı ve asistanın ekrana bakması.")
        case .fullDisk: return L("Odak modu göstergesi ve bildirimleri çentikte gösterme.")
        case .calendar: return L("Yaklaşan etkinlikler, toplantı geri sayımı, asistanın etkinlik eklemesi.")
        case .reminders: return L("Anımsatıcıları gösterme ve asistanın anımsatıcı eklemesi.")
        case .location: return L("Bulunduğunuz yerin hava durumu.")
        case .bluetooth: return L("Bağlanan cihazları ve pil düzeylerini gösterme.")
        case .camera: return L("Ayna.")
        case .microphone: return L("Asistanla sesli konuşma.")
        case .speech: return L("Söylediklerinizi yazıya çevirme.")
        }
    }

    /// Sistem Ayarları'ndaki ilgili bölüm.
    var settingsAnchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .screen: return "Privacy_ScreenCapture"
        case .fullDisk: return "Privacy_AllFiles"
        case .calendar: return "Privacy_Calendars"
        case .reminders: return "Privacy_Reminders"
        case .location: return "Privacy_LocationServices"
        case .bluetooth: return "Privacy_Bluetooth"
        case .camera: return "Privacy_Camera"
        case .microphone: return "Privacy_Microphone"
        case .speech: return "Privacy_SpeechRecognition"
        }
    }

    /// Yalnızca Sistem Ayarları'ndan verilebilen izinler (pencereyle sorulamaz).
    var settingsOnly: Bool { self == .fullDisk }

    var state: PermissionState {
        switch self {
        case .accessibility: return AXIsProcessTrusted() ? .granted : .denied
        case .screen: return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .fullDisk: return FullDiskAccess.granted ? .granted : .denied
        case .calendar: return Self.map(EKEventStore.authorizationStatus(for: .event))
        case .reminders: return Self.map(EKEventStore.authorizationStatus(for: .reminder))
        case .location:
            switch WeatherService.shared.authorization {
            case .notDetermined: return .notAsked
            case .denied, .restricted: return .denied
            default: return .granted
            }
        case .bluetooth:
            switch CBCentralManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .camera: return Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: return Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        }
    }

    private static func map(_ s: EKAuthorizationStatus) -> PermissionState {
        switch s {
        case .fullAccess: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    private static func map(_ s: AVAuthorizationStatus) -> PermissionState {
        switch s {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// İzni ister. macOS bir kez reddedilen izni yeniden sormaz; o durumda Sistem Ayarları açılır.
    func request(completion: @escaping () -> Void) {
        let done = { DispatchQueue.main.async { ModuleManager.shared.permissionsChanged(); completion() } }
        if state == .denied, self != .accessibility, self != .screen {
            openSettings()
            done()
            return
        }
        switch self {
        case .accessibility:
            MediaKeyTap.shared.requestTrust()
            done()
        case .screen:
            if !CGRequestScreenCaptureAccess() { openSettings() }
            done()
        case .fullDisk:
            openSettings()
            done()
        case .calendar:
            AgendaService.shared.store.requestFullAccessToEvents { _, _ in done() }
        case .reminders:
            AgendaService.shared.store.requestFullAccessToReminders { _, _ in done() }
        case .location:
            WeatherService.shared.requestPermission()
            done()
        case .bluetooth:
            BluetoothService.shared.requestPermission()
            done()
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in done() }
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in done() }
        case .speech:
            SFSpeechRecognizer.requestAuthorization { _ in done() }
        }
    }

    /// Bu izin, açık olan modüllerden biri için gerekli mi?
    var needed: Bool {
        let p = Prefs.shared
        switch self {
        case .accessibility: return p.isOn(.hud) || p.isOn(.assistant) || p.isOn(.clipboard)
        case .screen: return p.isOn(.lockscreen) || p.allowScreen
        case .fullDisk: return p.isOn(.focus) || p.isOn(.notifications)
        case .calendar: return p.isOn(.calendar)
        case .reminders: return p.isOn(.reminders)
        case .location: return p.isOn(.weather)
        case .bluetooth: return p.isOn(.bluetooth)
        case .camera: return p.isOn(.mirror)
        case .microphone, .speech: return p.isOn(.assistant)
        }
    }
}

struct PermissionsSettings: View {
    @ObservedObject var prefs = Prefs.shared
    @State private var tick = 0

    var body: some View {
        let kinds = PermissionKind.allCases
        let needed = kinds.filter(\.needed)
        let other = kinds.filter { !$0.needed }
        Form {
            Section {
                ForEach(needed) { row($0) }
            } header: {
                Text(L("Açık modüllerin kullandığı izinler"))
            } footer: {
                Text(L("Ada açılışta hiçbir izni kendiliğinden istemez. İstediğiniz izni buradan verin; vermedikleriniz yalnızca ilgili özelliği kapalı tutar. Erişilebilirlik ve Tam Disk Erişimi için listede eski bir Ada satırı varsa önce onu silin."))
            }
            if !other.isEmpty {
                Section(L("Şu an gerekmeyenler")) {
                    ForEach(other) { row($0) }
                }
            }
        }
        .formStyle(.grouped)
        .id(tick)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
    }

    private func row(_ kind: PermissionKind) -> some View {
        let state = kind.state
        return HStack(spacing: 10) {
            Image(systemName: kind.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background((state == .granted ? Color.green : Color.gray).gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).fontWeight(.medium)
                Text(kind.purpose).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch state {
            case .granted:
                Label(L("Verildi"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
            default:
                if kind.settingsOnly {
                    Button(L("Ayarı aç")) { kind.openSettings() }
                } else {
                    Button(state == .notAsked ? L("İzin ver") : L("İzin iste")) { kind.request { tick += 1 } }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
