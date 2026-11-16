import SwiftUI
import UniformTypeIdentifiers

struct NotchShape: Shape {
    var topRadius: CGFloat = 7
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let t = topRadius, b = min(bottomRadius, r.height / 2)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    @ObservedObject var model = NotchModel.shared
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var music = MusicService.shared
    @ObservedObject var countdown = CountdownService.shared
    @ObservedObject var agenda = AgendaService.shared

    var body: some View {
        let size = model.currentSize()
        let shape = NotchShape(bottomRadius: model.expanded ? prefs.cornerRadius : 10)
        let glassy = model.expanded && prefs.glass
        ZStack(alignment: .top) {
            NotchBackground(shape: shape, glassy: glassy, clarity: prefs.glassClarity,
                            blackBand: max(model.notchSize.height, 30) / model.expandedSize.height)
                .overlay(
                    shape.stroke(prefs.accentColor.opacity(model.dropTargeted ? 0.9 : 0), lineWidth: 2)
                )
                .shadow(color: .black.opacity(model.expanded ? (glassy ? 0.3 : 0.45) : 0), radius: 18, y: 10)
            Group {
                if model.expanded {
                    ExpandedView()
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    CollapsedView()
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $model.dropTargeted) { providers in
            guard prefs.isOn(.shelf) else { return false }
            ShelfService.shared.add(providers)
            model.expand(tab: .shelf)
            return true
        }
        .onChange(of: model.dropTargeted) { _, targeted in
            if targeted, prefs.isOn(.shelf) { model.expand(tab: .shelf) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: size)
        .animation(.easeInOut(duration: 0.2), value: model.tab)
        .preferredColorScheme(.dark)
    }
}

/// Çentiğin zemini. Kapalıyken düz siyah (fiziksel çentikle birleşir); açıkken üst şerit
/// siyah kalır ve aşağı doğru Liquid Glass'a karışır.
struct NotchBackground: View {
    var shape: NotchShape
    var glassy: Bool
    /// 0 = neredeyse opak siyah, 1 = tamamen saydam cam.
    var clarity: Double = 0.6
    /// Üstteki tam siyah şeridin yüksekliğe oranı.
    var blackBand: CGFloat

    var body: some View {
        ZStack {
            if glassy {
                let dark = (1 - clarity) * 0.9
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(clarity > 0.85 ? .clear : .regular.tint(.black.opacity(dark)), in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(.black.opacity(dark))
                }
                shape.fill(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: blackBand),
                    .init(color: .black.opacity(0.55), location: min(0.9, blackBand + 0.12)),
                    .init(color: .black.opacity(0.12), location: min(0.95, blackBand + 0.36)),
                    .init(color: .black.opacity(0.0), location: 1),
                ], startPoint: .top, endPoint: .bottom))
                // Camın kenarındaki ışık çizgisi
                shape.stroke(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: blackBand),
                    .init(color: .white.opacity(0.22), location: min(0.95, blackBand + 0.3)),
                    .init(color: .white.opacity(0.38), location: 1),
                ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            } else {
                shape.fill(Color.black)
            }
        }
    }
}

extension View {
    /// Cam üzerinde duran yarı saydam kart: hafif dolgu ve üstten vuran ışık kenarı.
    func glassCard<S: InsettableShape>(_ shape: S) -> some View {
        self.background(.white.opacity(0.10), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(0.30), .white.opacity(0.05)],
                startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
    }
}

// MARK: - Kapalı çentik

struct CollapsedView: View {
    @ObservedObject var model = NotchModel.shared
    @ObservedObject var music = MusicService.shared
    @ObservedObject var countdown = CountdownService.shared
    @ObservedObject var agenda = AgendaService.shared

    var body: some View {
        HStack(spacing: 0) {
            left.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: model.notchSize.width - 14)
            right.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { model.expand() }
    }

    @ViewBuilder var left: some View {
        if let hud = model.hud {
            HStack(spacing: 6) {
                Image(systemName: hud.icon).foregroundStyle(hud.tint)
                if hud.value != nil {
                    Text(hud.title).lineLimit(1)
                }
            }
            .font(.system(size: 12, weight: .semibold))
        } else if model.compactTimer {
            Image(systemName: countdown.pomodoro ? (countdown.working ? "brain.head.profile" : "cup.and.saucer.fill") : "timer")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        } else if model.compactMeeting, let e = agenda.next {
            HStack(spacing: 5) {
                Image(systemName: e.url != nil ? "video.fill" : "calendar").foregroundStyle(e.color)
                Text(e.title).lineLimit(1).truncationMode(.tail)
            }
            .font(.system(size: 11, weight: .semibold))
        } else if model.compactMusic {
            ArtworkView(image: music.artwork, size: 20, radius: 5)
        }
    }

    @ViewBuilder var right: some View {
        if let hud = model.hud {
            if let v = hud.value {
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule().fill(hud.tint).frame(width: max(4, geo.size.width * v))
                        }
                    }
                    .frame(width: 54, height: 5)
                    Text(hud.label ?? "\(Int((v * 100).rounded()))")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .frame(width: 30, alignment: .trailing)
                }
            } else {
                Text(hud.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
        } else if model.compactTimer {
            Text(formatClock(countdown.remaining))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
        } else if model.compactMeeting, let e = agenda.next {
            TimelineView(.periodic(from: .now, by: 20)) { _ in
                Text(e.countdown).font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
        } else if model.compactMusic {
            EqualizerBars().frame(width: 18, height: 14)
        }
    }
}

struct EqualizerBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let h = 0.3 + 0.7 * abs(sin(t * (2.1 + Double(i) * 0.7) + Double(i)))
                    Capsule().fill(Color.green).frame(width: 2.5, height: 14 * h)
                }
            }
        }
    }
}

// MARK: - Açık çentik

struct ExpandedView: View {
    @ObservedObject var model = NotchModel.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(spacing: 0) {
            TopBar().frame(height: max(model.notchSize.height, 30))
            Group {
                switch model.tab {
                case .home: HomeView()
                case .assistant: AssistantView()
                case .tools: ToolsView()
                case .shelf: ShelfView()
                case .apps: LauncherView()
                case .mirror: MirrorView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
    }
}

struct TopBar: View {
    @ObservedObject var model = NotchModel.shared
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var weather = WeatherService.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(model.availableTabs) { tab in
                    Button { model.tab = tab } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 22)
                            .background(model.tab == tab ? Color.white.opacity(0.20) : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(model.tab == tab ? 0.22 : 0), lineWidth: 0.8))
                            .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.55))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: model.notchSize.width - 10)

            HStack(spacing: 10) {
                if prefs.isOn(.weather), let w = weather.current {
                    Label("\(prefs.temp(w.temperature))°", systemImage: w.symbol)
                        .labelStyle(.titleAndIcon)
                }
                if prefs.isOn(.battery), let level = battery.level {
                    HStack(spacing: 3) {
                        Image(systemName: battery.symbol)
                            .foregroundStyle(battery.onAC ? .green : (level <= 20 ? .red : .white))
                        Text("%\(level)")
                    }
                }
                Button { AppDelegate.showSettings() } label: {
                    Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Ayarlar")
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
    }
}

// MARK: - Ana sekme

struct HomeView: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            if prefs.isOn(.music) {
                MusicCard().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if prefs.isOn(.calendar) || prefs.isOn(.reminders) || prefs.isOn(.weather) {
                AgendaColumn().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if !prefs.isOn(.music) && !prefs.isOn(.calendar) && !prefs.isOn(.reminders) && !prefs.isOn(.weather) {
                EmptyHint(icon: "square.dashed", text: "Ana sekmede gösterilecek modül açık değil.\nAyarlardan modülleri açabilirsiniz.")
            }
        }
    }
}

struct EmptyHint: View {
    var icon: String
    var text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.white.opacity(0.35))
            Text(text).font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.system(size: 9.5, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(.white.opacity(0.4))
    }
}

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.purple.opacity(0.7), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = .white.opacity(0.14)
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(LinearGradient(
                colors: [.white.opacity(0.32), .white.opacity(0.06)],
                startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
            .contentShape(Capsule())
    }
}
