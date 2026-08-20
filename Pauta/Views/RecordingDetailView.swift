import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Detalhe da gravação: player, transcrição e resumo com IA.
struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @StateObject private var player = AudioPlayerService()

    @State private var tab: DetailTab = .transcript
    @State private var template: SummaryTemplate = .meeting
    @State private var isGenerating = false
    @State private var isTranscribing = false
    @State private var isTitling = false
    @State private var streamText = ""
    @State private var errorMessage: String?

    @AppStorage("claudeModel") private var model = "claude-opus-5"
    @AppStorage("transcriptLocale") private var localeId = "pt-BR"

    enum DetailTab {
        case transcript, summary
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PlayerBar(player: player)
            Divider()

            Picker("Conteúdo", selection: $tab) {
                Text("Transcrição").tag(DetailTab.transcript)
                Text("Resumo IA").tag(DetailTab.summary)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            content
        }
        .toolbar { toolbarContent }
        .onAppear {
            if let url = recording.audioURL {
                player.load(url: url)
            }
        }
        .onDisappear {
            player.stop()
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Título", text: $recording.title)
                .font(.title2.bold())
                .textFieldStyle(.plain)
            HStack(spacing: 8) {
                Text(recording.createdAt, format: .dateTime.day().month(.wide).year().hour().minute())
                Text("•")
                Text(TimeFormat.string(recording.duration))
                if recording.audioURL == nil {
                    Text("•")
                    Label("Áudio indisponível", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    suggestTitle()
                } label: {
                    Label(isTitling ? "Sugerindo título…" : "Sugerir título com IA", systemImage: "wand.and.stars")
                }
                .disabled(isTitling || recording.transcript.isEmpty)

                Menu {
                    ForEach(SummaryTemplate.allCases) { tmpl in
                        Button(tmpl.name) {
                            template = tmpl
                            generateSummary()
                        }
                    }
                } label: {
                    Label("Gerar resumo…", systemImage: "sparkles")
                }
                .disabled(isGenerating || recording.transcript.isEmpty)

                Divider()

                Button {
                    copyToPasteboard(recording.transcript)
                } label: {
                    Label("Copiar transcrição", systemImage: "doc.on.doc")
                }
                .disabled(recording.transcript.isEmpty)

                Button {
                    copyToPasteboard(recording.summary)
                } label: {
                    Label("Copiar resumo", systemImage: "doc.on.doc.fill")
                }
                .disabled(recording.summary.isEmpty)

                if let url = recording.audioURL {
                    ShareLink(item: url) {
                        Label("Compartilhar áudio", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label("Ações", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Conteúdo

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .transcript:
            ScrollView {
                if recording.transcript.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "text.quote")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Esta gravação ainda não tem transcrição.")
                            .foregroundStyle(.secondary)
                        Button(isTranscribing ? "Transcrevendo…" : "Transcrever áudio") {
                            transcribe()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTranscribing || recording.audioURL == nil)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    Text(recording.transcript)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        case .summary:
            ScrollView {
                if isGenerating {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Gerando com o Claude…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        MarkdownText(text: streamText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                } else if !recording.summary.isEmpty {
                    MarkdownText(text: recording.summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.largeTitle)
                            .foregroundStyle(Color.accentColor)
                        Text("Transforme a transcrição em ata, notas ou resumo.")
                            .foregroundStyle(.secondary)
                        Picker("Modelo de resumo", selection: $template) {
                            ForEach(SummaryTemplate.allCases) { tmpl in
                                Text(tmpl.name).tag(tmpl)
                            }
                        }
                        .frame(maxWidth: 280)
                        Button("Gerar resumo com IA") {
                            generateSummary()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(recording.transcript.isEmpty)
                        if recording.transcript.isEmpty {
                            Text("Transcreva o áudio primeiro, na aba Transcrição.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
        }
    }

    // MARK: - Ações

    private func transcribe() {
        guard let url = recording.audioURL else { return }
        isTranscribing = true
        errorMessage = nil
        Task {
            do {
                let text = try await TranscriptionService.transcribe(url: url, localeId: localeId)
                await MainActor.run {
                    recording.transcript = text
                    recording.transcriptLocale = localeId
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isTranscribing = false
                }
            }
        }
    }

    private func generateSummary() {
        guard !recording.transcript.isEmpty else { return }
        guard let apiKey = KeychainHelper.load(key: ClaudeService.apiKeyKeychainKey), !apiKey.isEmpty else {
            errorMessage = ClaudeError.missingKey.localizedDescription
            return
        }
        tab = .summary
        isGenerating = true
        streamText = ""
        errorMessage = nil
        let transcript = recording.transcript
        let chosenTemplate = template
        let chosenModel = model
        Task {
            do {
                let text = try await ClaudeService.streamCompletion(
                    system: chosenTemplate.systemPrompt,
                    user: "Transcrição da gravação:\n\n\(transcript)",
                    model: chosenModel,
                    apiKey: apiKey
                ) { delta in
                    Task { @MainActor in
                        streamText += delta
                    }
                }
                await MainActor.run {
                    recording.summary = text
                    recording.summaryTemplateRaw = chosenTemplate.rawValue
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func suggestTitle() {
        guard !recording.transcript.isEmpty else { return }
        guard let apiKey = KeychainHelper.load(key: ClaudeService.apiKeyKeychainKey), !apiKey.isEmpty else {
            errorMessage = ClaudeError.missingKey.localizedDescription
            return
        }
        isTitling = true
        errorMessage = nil
        let excerpt = String(recording.transcript.prefix(3000))
        let chosenModel = model
        Task {
            do {
                let title = try await ClaudeService.complete(
                    system: "Você cria títulos para gravações de voz. Responda apenas com um título curto (máximo 8 palavras), em português, sem aspas nem ponto final.",
                    user: "Crie um título para esta gravação:\n\n\(excerpt)",
                    model: chosenModel,
                    apiKey: apiKey,
                    maxTokens: 300
                )
                await MainActor.run {
                    let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        recording.title = cleaned
                    }
                    isTitling = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isTitling = false
                }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Renderiza Markdown simples linha a linha (títulos, listas e ênfases).
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("### ") {
            Text(inline(String(trimmed.dropFirst(4))))
                .font(.headline)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("## ") {
            Text(inline(String(trimmed.dropFirst(3))))
                .font(.title3.bold())
                .padding(.top, 6)
        } else if trimmed.hasPrefix("# ") {
            Text(inline(String(trimmed.dropFirst(2))))
                .font(.title2.bold())
                .padding(.top, 6)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                Text(inline(String(trimmed.dropFirst(2))))
            }
        } else if trimmed.isEmpty {
            Spacer().frame(height: 2)
        } else {
            Text(inline(trimmed))
        }
    }

    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string)) ?? AttributedString(string)
    }
}

struct PlayerBar: View {
    @ObservedObject var player: AudioPlayerService

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 28) {
                Button {
                    player.skip(-15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                }
                Button {
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                }
                Button {
                    player.skip(15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                }
                Menu {
                    ForEach([Float(1.0), 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button(String(format: "%gx", speed)) {
                            player.setRate(speed)
                        }
                    }
                } label: {
                    Text(String(format: "%gx", player.rate))
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 44)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Text(TimeFormat.string(player.progress))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.01)
                )
                Text(TimeFormat.string(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .disabled(player.duration == 0)
    }
}
