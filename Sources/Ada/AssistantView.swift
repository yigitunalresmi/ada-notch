import SwiftUI

struct AssistantView: View {
    @ObservedObject var engine = AssistantEngine.shared
    @ObservedObject var speech = SpeechService.shared
    @ObservedObject var model = NotchModel.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if !engine.hasKey {
            VStack(spacing: 10) {
                Image(systemName: "key.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                Text(L("Asistanı kullanmak için Anthropic API anahtarınızı ekleyin."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                Button(L("Ayarları Aç")) { AppDelegate.showSettings() }
                    .buttonStyle(PillButtonStyle(tint: Prefs.shared.accentColor.opacity(0.8)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { engine.refreshKey() }
        } else {
            VStack(spacing: 8) {
                conversation
                if let p = engine.pending { confirmCard(p) }
                SelectionCard()
                inputBar
            }
            .onAppear {
                focusSoon()
                speech.autoSend = { text in
                    draft = ""
                    engine.send(text)
                }
            }
            .onChange(of: model.focusInput) { _, _ in focusSoon() }
            .onChange(of: speech.transcript) { _, t in if speech.listening { draft = t } }
        }
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    if engine.items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Merhaba, ben Ada.")).font(.system(size: 14, weight: .semibold))
                            Text(L("Şunları deneyebilirsiniz:")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach([L("Günün özetini ver"), L("Bugün takvimimde ne var?"), L("Bu pencereyi sola yasla"), L("Seçili metni özetle"), L("25 dakikalık zamanlayıcı kur"), L("Sesi yüzde 30 yap ve karanlık moda geç"), L("Yarın 10'a toplantı ekle")], id: \.self) { s in
                                        Button(s) { engine.send(s) }.buttonStyle(PillButtonStyle()).fixedSize()
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(.top, 2)
                    }
                    ForEach(engine.items) { item in
                        bubble(item).id(item.id)
                    }
                    if engine.busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(engine.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        }
                        .id("busy")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: engine.items.count) { _, _ in
                withAnimation { proxy.scrollTo(engine.busy ? AnyHashable("busy") : AnyHashable(engine.items.last?.id), anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private func bubble(_ item: ChatItem) -> some View {
        switch item.role {
        case .user:
            Text(item.text)
                .font(.system(size: 12.5))
                .lineLimit(5)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Prefs.shared.accentColor.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        case .assistant:
            TypewriterText(text: item.text,
                           animate: !Prefs.shared.reduceMotion && !engine.revealed.contains(item.id) && item.id == engine.items.last(where: { $0.role == .assistant })?.id,
                           onFinished: { engine.revealed.insert(item.id) })
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .frame(maxWidth: 560, alignment: .leading)
                .textSelection(.enabled)
        case .tool:
            Label(item.text, systemImage: "bolt.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        case .error:
            Label(item.text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    private func confirmCard(_ p: PendingConfirm) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.title).font(.system(size: 12, weight: .semibold))
                ScrollView {
                    Text(p.detail).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 54)
            }
            VStack(spacing: 5) {
                Button(L("Onayla")) { engine.resolve(true) }.buttonStyle(PillButtonStyle(tint: .green.opacity(0.7)))
                Button(L("Reddet")) { engine.resolve(false) }.buttonStyle(PillButtonStyle(tint: .red.opacity(0.6)))
            }
        }
        .padding(9)
        .glassCard(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                speech.toggle { text in
                    draft = ""
                    engine.send(text)
                }
            } label: {
                Image(systemName: speech.listening ? "waveform" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(speech.listening ? .red : .white.opacity(0.7))
                    .symbolEffect(.variableColor, isActive: speech.listening)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(speech.listening ? L("Dinlemeyi bitir ve gönder") : L("Sesle sor"))

            Button { speech.setConversation(!speech.conversation) } label: {
                Image(systemName: speech.conversation ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(speech.conversation ? Prefs.shared.accentColor : .white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(speech.conversation ? L("Sesli sohbeti bitir") : L("Sesli sohbet: konuşun, susunca gönderilir, yanıt sesli okunur"))

            TextField(speech.listening ? L("Dinliyorum…") : (speech.error ?? L("Ada'ya sorun ya da bir şey yaptırın")), text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(submit)
                .onTapGesture { NotchController.shared.makeKey() }

            if engine.busy {
                Button { engine.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 17)).foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain).help(L("Durdur"))
            } else {
                if !engine.items.isEmpty {
                    Button { engine.reset(); SpeechService.shared.stopSpeaking() } label: {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain).help(L("Sohbeti temizle"))
                }
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 19))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.25) : .white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassCard(Capsule())
    }

    private func submit() {
        if speech.listening { speech.stop() }
        let text = draft
        draft = ""
        engine.send(text)
    }
}
