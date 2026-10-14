import SwiftUI

/// Ask about the book you are reading (design D6, AI-panel D4–D7 on the Mac).
///
/// Everything here is presentation. What a prompt contains, whether the model knows this book, and
/// the sentence about where a question goes are the Mac's and arrive as events; the session turns
/// them into state; this view draws it. In particular the disclosure line is **the Mac's string,
/// shown verbatim** — the phone does not compose a claim about what is sent.
struct AskSheet: View {
    let session: AskSession
    let toc: [ReaderTocEntry]
    let onGoTo: (ReaderTocEntry) -> Void

    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch session.availability {
                case .checking:
                    Spacer()
                    ProgressView().tint(Palette.gold)
                    Spacer()
                case let .unavailable(reason):
                    unavailable(reason)
                case let .ready(capability):
                    transcript(capability)
                    composer(capability)
                }
            }
            .background(Palette.surface)
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.surface)
        .task { await session.open() }
        // Leaving the sheet is leaving the question: the stream is cancelled, a partial answer stays.
        .onDisappear { session.cancel() }
    }

    // MARK: states

    private func unavailable(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.bubble").font(.largeTitle).foregroundStyle(Palette.muted)
            Text("Ask is not available").font(.display(18)).foregroundStyle(Palette.parchment)
            Text(reason).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func transcript(_ capability: AskCapability) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    notice
                    ForEach(session.turns) { turn in
                        bubble(turn)
                            .id(turn.id)
                        if turn.role == .model, !turn.streaming {
                            ForEach(AskCitations.entries(in: turn.text, toc: toc)) { entry in
                                Button { onGoTo(entry) } label: {
                                    Label("Go to “\(entry.title)”", systemImage: "arrow.turn.down.right")
                                        .font(.footnote)
                                }
                                .foregroundStyle(Palette.gold)
                            }
                        }
                    }
                    if let failure = session.failure {
                        Text(failure).font(.footnote).foregroundStyle(Palette.danger)
                    }
                }
                .padding(16)
            }
            .onChange(of: session.turns.last?.text) { _, _ in
                if let last = session.turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    /// What the probe found, in the Mac panel's own words (AI-panel D6).
    @ViewBuilder private var notice: some View {
        if session.probing {
            Text("Checking whether the model knows this book…").font(.footnote).foregroundStyle(Palette.muted)
        } else if session.verdict == .weak {
            Text("The model couldn't place this book — sending the passage for this session.")
                .font(.footnote).foregroundStyle(Palette.gold)
        } else if session.verdict == .unknown {
            Text("Unverified — answers about this book are reconstructed, not recalled.")
                .font(.footnote).foregroundStyle(Palette.muted)
        }
    }

    private func bubble(_ turn: AskSession.Turn) -> some View {
        Text(turn.text + (turn.streaming ? " ▍" : ""))
            .font(turn.role == .model ? .display(16) : .subheadline)
            .foregroundStyle(turn.role == .model ? Palette.parchment : Palette.gold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    // MARK: the composer

    private func composer(_ capability: AskCapability) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = session.disclosure {
                Text(line.text).font(.caption).foregroundStyle(Palette.muted)
            }
            Text(
                capability.isLocal
                    ? "Local — nothing leaves your Mac."
                    : "Remote — \(capability.host) receives this."
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(capability.isLocal ? Palette.muted : Palette.gold)

            Toggle(
                "Send the passage too",
                isOn: Binding(
                    get: { session.rung == .passage },
                    set: { on in Task { await session.setPassageOverride(on) } })
            )
            .font(.footnote)
            .tint(Palette.gold)
            .disabled(session.verdict == .weak)

            HStack(spacing: 8) {
                TextField("Ask about this passage", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Palette.parchment)
                Button {
                    let question = draft
                    draft = ""
                    session.ask(question)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .foregroundStyle(Palette.gold)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isAnswering)
                .accessibilityLabel("Send")
            }
        }
        .padding(16)
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}
