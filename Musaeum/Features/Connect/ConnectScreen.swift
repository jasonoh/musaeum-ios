import SwiftUI

/// Where the phone is told about the Mac. Two fields and one button: the URL and
/// the bearer token are read off Musaeum's own Settings row on the Mac (which
/// shows the full URL precisely so it can be typed in by hand), and the connect
/// check is the contract's own `GET /api/health`.
struct ConnectScreen: View {
    @Environment(SettingsStore.self) private var settings

    @State private var base: String = ""
    @State private var token: String = ""
    @State private var phase: Phase = .idle
    @State private var revealToken = false

    enum Phase: Equatable {
        case idle
        case checking
        case connected(Health)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 8) {
                    field("The Mac's address", text: $base, prompt: "host:8788")
                    field("Bearer token", text: $token, prompt: "64 hex characters", secure: !revealToken)
                    Toggle("Show the token", isOn: $revealToken)
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                    Text("Both are on the Mac: Musaeum → Settings → Phone access. Turning its switch on generates the token.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }

                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        if phase == .checking { ProgressView().tint(Palette.ink) }
                        Text("Check the connection")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.gold, in: .rect(cornerRadius: 12))
                    .foregroundStyle(Palette.ink)
                }
                .disabled(phase == .checking || base.isEmpty || token.isEmpty)

                result

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .onAppear {
            base = settings.baseURLString
            token = settings.token
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Wordmark(size: 34)
                .accessibilityAddTraits(.isHeader)
            Text("Your library lives on the Mac. Point this phone at it over the tailnet to browse, download and read.")
                .font(.callout)
                .foregroundStyle(Palette.muted)
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            Group {
                if secure {
                    SecureField(prompt, text: text)
                } else {
                    TextField(prompt, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(secure ? .default : .URL)
            .padding(12)
            .background(Palette.surface, in: .rect(cornerRadius: 10))
            .foregroundStyle(Palette.parchment)
        }
    }

    @ViewBuilder
    private var result: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .checking:
            Text("Asking the Mac…").font(.footnote).foregroundStyle(Palette.muted)
        case let .connected(health):
            VStack(alignment: .leading, spacing: 6) {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.gold)
                Text("Musaeum \(health.version) · contract v\(health.apiVersion) · \(health.books) books · library \(health.library.rawValue)")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: .rect(cornerRadius: 12))
        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Not connected", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.danger)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: .rect(cornerRadius: 12))
        }
    }

    private func check() async {
        guard let url = URL(string: SettingsStore.normalizeBase(base) ?? base) else {
            phase = .failed(ClientError.badBaseURL(base).description)
            return
        }
        phase = .checking
        let client = MusaeumClient(base: url, token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            let health = try await client.health()
            settings.save(base: base, token: token)
            phase = .connected(health)
            Probe.log("connect ok apiVersion=\(health.apiVersion) books=\(health.books) library=\(health.library.rawValue)")
        } catch let error as ClientError {
            phase = .failed(error.description)
            Probe.log("connect failed \(error)")
        } catch {
            phase = .failed(String(describing: error))
            Probe.log("connect failed \(error)")
        }
    }
}
