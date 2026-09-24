import SwiftUI

/// The upload's own surface: the picker, what the send is doing, and what the Mac
/// said — with the controls that are honest for each refusal class.
///
/// **The row says nothing the Mac has not said.** Until a `201` arrives, this
/// screen does not claim a book is in the library — the distinction the annex's
/// sixth criterion is about, and the reason `UploadModel.claimsBookIsInLibrary`
/// exists rather than the view inferring it from "the request was sent".
///
/// **The picker is the one place a `fileImporter` appears**, and the formats it
/// offers are the contract's own four (`UploadFile.contentTypes`). Which format
/// travels is the file's own extension's answer, never the picker's.
struct UploadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    let model: UploadModel
    let client: MusaeumClient

    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    UploadStatusRow(model: model) {
                        Task { await model.retry(to: client) }
                    } reconnect: {
                        // Clearing the credential is the way back to the connect
                        // screen (this app has no Settings surface of its own), and
                        // the sheet has to get out of its way for the reader to see
                        // it.
                        settings.clear()
                        dismiss()
                    } dismissOutcome: {
                        model.reset()
                    }
                    controls

                    Text("“Copy to Musaeum” works too: from Files, Safari or Mail, share the file to Musaeum and the app takes it the same way.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                .padding(16)
            }
            .background(Palette.ink)
            .navigationTitle("Send a book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Palette.gold)
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: UploadFile.contentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                // The scope is open for the length of this callback, which is why
                // the copy into the app's own container happens *inside* it
                // (`UploadFile.stage`) rather than when the send gets to it.
                Task { await model.send(file: url, to: client) }
            case let .failure(error):
                model.pickingFailed(error)
            }
        }
    }

    /// **Only the picker lives here.** *Try again*, *Reconnect* and *Dismiss* are
    /// the row's own controls — they are about the outcome above them, and two
    /// buttons doing the same thing on one screen is how the two drift apart.
    @ViewBuilder
    private var controls: some View {
        if model.isSending {
            HStack(spacing: 8) {
                ProgressView().tint(Palette.gold)
                Text("The Mac is taking the bytes. A large book can take a while over a tailnet.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
        } else {
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                    Text(model.claimsBookIsInLibrary ? "Send another book" : "Choose a file…")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Palette.gold, in: .rect(cornerRadius: 10))
                .foregroundStyle(Palette.ink)
            }
            .buttonStyle(.plain)
        }
    }
}

/// **The upload's state drawn the same wherever it is shown** — the sheet's own
/// row, and the library screen's, so an outcome is not lost when the sheet closes.
/// One view, so the two surfaces cannot describe the same refusal differently.
struct UploadStatusRow: View {
    let model: UploadModel
    var retry: () -> Void = {}
    var reconnect: () -> Void = {}
    var dismissOutcome: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if model.isSending {
                    ProgressView().tint(Palette.gold)
                } else {
                    Image(systemName: glyph)
                        .foregroundStyle(tint)
                }
                Text(model.title)
                    .font(.display(17, weight: .semibold))
                    .foregroundStyle(Palette.parchment)
            }
            Text(model.message)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
            if let advice = model.advice {
                Text(advice)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            if !model.isSending, model.outcome != nil {
                HStack(spacing: 12) {
                    if model.offersRetry {
                        Button("Try again", action: retry)
                    }
                    if model.offersReconnect {
                        Button("Reconnect", action: reconnect)
                    }
                    Button("Dismiss", action: dismissOutcome)
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Palette.gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.raised, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Palette.hairline, lineWidth: 1)
        )
    }

    /// A `201` is the only thing that draws a tick: the glyph beside the row is
    /// the claim, and it is the model's own answer rather than the view's guess.
    private var glyph: String {
        switch model.outcome {
        case .added: "checkmark.circle.fill"
        case .refused: "exclamationmark.triangle"
        case nil: "arrow.up.circle"
        }
    }

    private var tint: Color {
        switch model.outcome {
        case .added: Palette.gold
        case .refused: Palette.danger
        case nil: Palette.muted
        }
    }
}
