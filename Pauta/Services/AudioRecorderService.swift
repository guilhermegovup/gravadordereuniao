import Foundation
import AVFoundation
import Speech

/// Grava áudio com AVAudioEngine e transcreve ao vivo com SFSpeechRecognizer.
/// Um único tap no microfone alimenta o arquivo .m4a, o medidor de nível e o
/// reconhecimento de fala (que é reiniciado periodicamente para suportar
/// gravações longas).
final class AudioRecorderService: ObservableObject {
    enum RecState {
        case idle, recording, paused, stopped
    }

    struct RecordingResult {
        let fileName: String
        let duration: TimeInterval
        let transcript: String
    }

    @Published var state: RecState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var levels: [Float] = Array(repeating: 0, count: 48)
    @Published var liveTranscript: String = ""
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var fileName = ""
    private var timer: Timer?
    private var segmentStart: Date?
    private var accumulatedTime: TimeInterval = 0

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalized = ""
    private var partial = ""
    private var lastRecognitionRestart = Date()
    private var speechEnabled = false

    // MARK: - Ciclo de vida

    func start(localeId: String) async {
        guard state == .idle else { return }

        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard micGranted else {
            await MainActor.run {
                errorMessage = "Permissão de microfone negada. Libere o acesso em Ajustes do sistema."
            }
            return
        }

        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        speechEnabled = speechStatus == .authorized

        await MainActor.run {
            do {
                try self.startEngine(localeId: localeId)
            } catch {
                self.errorMessage = "Não foi possível iniciar a gravação: \(error.localizedDescription)"
            }
        }
    }

    private func startEngine(localeId: String) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Pauta", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microfone indisponível."])
        }

        let (url, name) = AudioStore.newFile()
        fileName = name
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])

        if speechEnabled {
            let locale = Locale(identifier: localeId)
            recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
            if recognizer?.isAvailable == true {
                startRecognitionSegment()
            } else {
                recognizer = nil
            }
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handle(buffer: buffer)
        }

        engine.prepare()
        try engine.start()

        state = .recording
        segmentStart = Date()
        accumulatedTime = 0
        startTimer()
    }

    func pause() {
        guard state == .recording else { return }
        engine.pause()
        if let start = segmentStart {
            accumulatedTime += Date().timeIntervalSince(start)
        }
        segmentStart = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        do {
            try engine.start()
            segmentStart = Date()
            state = .recording
        } catch {
            errorMessage = "Não foi possível retomar: \(error.localizedDescription)"
        }
    }

    /// Encerra e devolve o resultado (nil se nada foi gravado).
    func stop() -> RecordingResult? {
        guard state == .recording || state == .paused else { return nil }
        if state == .recording, let start = segmentStart {
            accumulatedTime += Date().timeIntervalSince(start)
        }
        teardown()
        commitPartial()
        publishTranscript()
        state = .stopped
        return RecordingResult(fileName: fileName, duration: accumulatedTime, transcript: finalized)
    }

    /// Descarta a gravação em andamento e apaga o arquivo.
    func cancel() {
        let name = fileName
        if state == .recording || state == .paused {
            teardown()
        }
        state = .stopped
        AudioStore.delete(name)
    }

    private func teardown() {
        timer?.invalidate()
        timer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        file = nil // fecha o arquivo
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Áudio (thread de captura)

    private func handle(buffer: AVAudioPCMBuffer) {
        try? file?.write(from: buffer)
        request?.append(buffer)

        let level = Self.rmsLevel(buffer: buffer)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .recording else { return }
            if !self.levels.isEmpty { self.levels.removeFirst() }
            self.levels.append(level)
        }
    }

    private static func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            sum += data[i] * data[i]
        }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 0.00001))
        return max(0, min(1, (db + 50) / 50))
    }

    // MARK: - Reconhecimento de fala

    private func startRecognitionSegment() {
        guard let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req
        lastRecognitionRestart = Date()
        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let result else { return } // erros de segmentos cancelados são ignorados
                self.partial = result.bestTranscription.formattedString
                if result.isFinal {
                    self.commitPartial()
                    if self.state == .recording {
                        self.startRecognitionSegment()
                    }
                }
                self.publishTranscript()
            }
        }
    }

    /// O reconhecimento de fala tem limite prático de duração por requisição;
    /// a cada ~50s finalizamos o segmento atual e abrimos outro.
    private func rotateRecognitionIfNeeded() {
        guard state == .recording, request != nil else { return }
        guard Date().timeIntervalSince(lastRecognitionRestart) > 50 else { return }
        request?.endAudio()
    }

    private func commitPartial() {
        let piece = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !piece.isEmpty {
            finalized += finalized.isEmpty ? piece : " " + piece
        }
        partial = ""
    }

    private func publishTranscript() {
        if partial.isEmpty {
            liveTranscript = finalized
        } else {
            liveTranscript = finalized.isEmpty ? partial : finalized + " " + partial
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.state == .recording, let start = self.segmentStart {
                self.elapsed = self.accumulatedTime + Date().timeIntervalSince(start)
            }
            self.rotateRecognitionIfNeeded()
        }
    }
}
