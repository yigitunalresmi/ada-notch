import AppKit
import SwiftUI

// MARK: - Konfeti (zamanlayıcı bittiğinde)

struct CelebrationLayer: View {
    @ObservedObject var model = NotchModel.shared
    @State private var start = Date.distantPast
    @State private var seed = 0

    private let duration = 1.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: Date().timeIntervalSince(start) > duration)) { ctx in
            let t: Double = ctx.date.timeIntervalSince(start)
            Canvas { g, size in
                guard t >= 0, t < duration else { return }
                var rng = SeededRandom(seed: UInt64(seed &+ 1))
                let originX: Double = Double(size.width) / 2
                let originY: Double = Double(model.notchSize.height)
                let colors: [Color] = [Prefs.shared.themeColor1, Prefs.shared.themeColor2, Prefs.shared.accentColor, .yellow, .white]
                for i in 0..<46 {
                    let angle: Double = rng.next(-1.25, 1.25)
                    let speed: Double = rng.next(90, 260)
                    let spin: Double = rng.next(-6, 6)
                    let w: Double = rng.next(4, 8)
                    let x: Double = originX + sin(angle) * speed * t
                    let y: Double = originY + cos(angle) * speed * t * 0.55 + 240 * t * t
                    let fade: Double = max(0, 1 - t / duration)
                    var piece = g
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(spin * t))
                    piece.opacity = fade
                    let rect = CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)
                    piece.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: model.celebration) { _, _ in
            guard !Prefs.shared.reduceMotion else { return }
            seed = model.celebration
            start = Date()
        }
    }
}

/// Aynı tohumla aynı diziyi üreten küçük rastgele sayı üreteci (her karede aynı parçacıklar çizilsin diye).
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next(_ lo: Double, _ hi: Double) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        return lo + (hi - lo) * unit
    }
}

// MARK: - Düşünme / dinleme ışıltısı

/// Asistan yanıt hazırlarken ya da dinlerken çentiğin kenarında dolaşan ışık.
struct ActivityGlow: View {
    var shape: NotchShape
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t: Double = ctx.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(t.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360)
            let pulse: Double = 0.55 + 0.35 * sin(t * 3.0)
            let ring = AngularGradient(colors: [color.opacity(0), color, .white, color, color.opacity(0)], center: .center, angle: angle)
            ZStack {
                shape.stroke(ring, lineWidth: 6).blur(radius: 8).opacity(pulse)
                shape.stroke(ring, lineWidth: 1.6)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Yazı efekti (asistan yanıtları)

struct TypewriterText: View {
    var text: String
    var animate: Bool
    var onFinished: () -> Void

    @State private var shown = 0
    @State private var timer: Timer?

    var body: some View {
        Group {
            if animate, shown < text.count {
                Text(String(text.prefix(shown)))
            } else {
                Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            }
        }
        .onAppear {
            guard animate, timer == nil, shown < text.count else { return }
            // Uzun yanıtlar da yaklaşık bir buçuk saniyede tamamlansın.
            let step = max(2, text.count / 90)
            let t = Timer(timeInterval: 0.016, repeats: true) { tm in
                shown = min(text.count, shown + step)
                if shown >= text.count {
                    tm.invalidate()
                    timer = nil
                    onFinished()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            if animate { onFinished() }
        }
    }
}

// MARK: - Mini grafik

struct Sparkline: View {
    var values: [Double]

    var body: some View {
        GeometryReader { geo in
            let w: Double = Double(geo.size.width), h: Double = Double(geo.size.height)
            Path { p in
                guard values.count > 1 else { return }
                let stepX: Double = w / Double(values.count - 1)
                // Küçük değişimler de görünsün diye en yüksek değere göre ölçekle.
                let top: Double = max(0.25, values.max() ?? 1)
                for (i, v) in values.enumerated() {
                    let x: Double = Double(i) * stepX
                    let y: Double = h - min(1, max(0, v / top)) * (h - 1)
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Prefs.shared.accentColor, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            .animation(.linear(duration: 0.4), value: values)
        }
    }
}

// MARK: - Saatlik hava tahmini

struct HourForecast: Identifiable, Equatable {
    var id: Date { time }
    var time: Date
    var temperature: Double
    var code: Int
    var isDay: Bool
    var rain: Int
}

// MARK: - Ekran görüntülerini rafa ekleme

/// Yeni alınan ekran görüntülerini Spotlight üzerinden yakalar ve dosya rafına ekler.
final class ScreenshotWatcher: NSObject {
    static let shared = ScreenshotWatcher()
    private var query: NSMetadataQuery?
    private var ready = false

    func setEnabled(_ on: Bool) {
        if on, query == nil {
            let q = NSMetadataQuery()
            q.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
            q.searchScopes = [NSMetadataQueryUserHomeScope]
            NotificationCenter.default.addObserver(self, selector: #selector(gathered), name: .NSMetadataQueryDidFinishGathering, object: q)
            NotificationCenter.default.addObserver(self, selector: #selector(updated(_:)), name: .NSMetadataQueryDidUpdate, object: q)
            ready = false
            q.start()
            query = q
        } else if !on, let q = query {
            q.stop()
            NotificationCenter.default.removeObserver(self, name: nil, object: q)
            query = nil
        }
    }

    @objc private func gathered() { ready = true }

    @objc private func updated(_ note: Notification) {
        guard ready, let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] else { return }
        for item in added {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                guard Prefs.shared.isOn(.shelf) else { return }
                if !ShelfService.shared.items.contains(url) { ShelfService.shared.items.append(url) }
                if Opt.flag("screenshots.hud") {
                    NotchModel.shared.showHUD(HUDInfo(icon: "camera.viewfinder", title: L("Rafa eklendi"),
                                                      image: NSImage(contentsOf: url), leftText: L("Ekran görüntüsü"), wide: true), seconds: 2.8)
                }
            }
        }
    }
}

// MARK: - Seçili metin için hızlı işlemler

struct SelectionCard: View {
    @ObservedObject var engine = AssistantEngine.shared

    var body: some View {
        if let text = engine.selection {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Image(systemName: "text.cursor").foregroundStyle(.white.opacity(0.5))
                    Text(text).font(.system(size: 11)).lineLimit(2).foregroundStyle(.white.opacity(0.75))
                    Spacer(minLength: 4)
                    Button { engine.selection = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5)) }
                        .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        action(L("Özetle"), L("Bu metni kısaca özetle"))
                        action(appLanguage == "tr" ? "Türkçeye çevir" : "Translate to English",
                               appLanguage == "tr" ? "Bu metni Türkçeye çevir" : "Translate this text to English")
                        action(L("Yazımı düzelt"), L("Bu metnin yazım ve dil bilgisi hatalarını düzelt, yalnızca düzeltilmiş metni ver"))
                        action(L("Açıkla"), L("Bu metni basitçe açıkla"))
                        action(L("Yanıt yaz"), L("Bu mesaja kısa ve kibar bir yanıt yaz"))
                    }
                }
            }
            .padding(8)
            .glassCard(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func action(_ title: String, _ instruction: String) -> some View {
        Button(title) {
            guard let text = engine.selection else { return }
            engine.selection = nil
            engine.send(instruction + ":\n\n" + text)
        }
        .buttonStyle(PillButtonStyle(tint: Prefs.shared.accentColor.opacity(0.6)))
        .fixedSize()
    }
}
