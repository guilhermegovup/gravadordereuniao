import SwiftUI
import SwiftData

/// Tela de gravação: cronômetro, forma de onda e transcrição ao vivo.
struct RecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @StateObject private var recorder = AudioRecorderService()
    @AppStorage("transcriptLocale") private var localeId = "pt-BR"

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            HStack(spacing: 8) {
                Circle()
                    .fill(recorder.state == .recording ? .red : .secondary)
                    .frame(width: 10, height: 10)
                Text(statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(TimeFormat.string(recorder.elapsed))
                .font(.system(size: 56, weight: .light, design: .monospaced))

            WaveformView(levels: recorder.levels)

            ScrollView {
                Text(recorder.liveTranscript.isEmpty
                     ? "A transcrição ao vivo aparece aqui enquanto você fala…"
                     : recorder.liveTranscript)
                    .font(.callout)
                    .foregroundStyle(recorder.liveTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxHeight: 180)

            if let error = recorder.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 44) {
                Button {
                    recorder.state == .paused ? recorder.resume() : recorder.pause()
                } label: {
                    Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .background(.quaternary, in: Circle())
                }
                .disabled(recorder.state != .recording && recorder.state != .paused)

                Button(action: finish) {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 76, height: 76)
                        Image(systemName: "stop.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
                .disabled(recorder.state != .recording && recorder.state != .paused)

                Button {
                    recorder.cancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .background(.quaternary, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(minWidth: 480, minHeight: 560)
        .interactiveDismissDisabled()
        .task {
            await recorder.start(localeId: localeId)
        }
    }

    private var statusLabel: String {
        switch recorder.state {
        case .idle: return "Preparando…"
        case .recording: return "Gravando"
        case .paused: return "Pausado"
        case .stopped: return "Encerrado"
        }
    }

    private func finish() {
        guard let result = recorder.stop() else {
            dismiss()
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d 'de' MMM, HH:mm"
        let recording = Recording(
            title: "Gravação de \(formatter.string(from: .now))",
            duration: result.duration,
            audioFileName: result.fileName,
            transcript: result.transcript,
            transcriptLocale: localeId
        )
        context.insert(recording)
        try? context.save()
        dismiss()
    }
}

struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: max(4, CGFloat(level) * 80))
            }
        }
        .frame(height: 90)
        .animation(.linear(duration: 0.15), value: levels)
    }
}
