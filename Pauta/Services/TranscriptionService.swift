import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case notAuthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Permissão de reconhecimento de fala negada. Libere o acesso em Ajustes do sistema."
        case .unavailable:
            return "Reconhecimento de fala indisponível para este idioma neste aparelho."
        }
    }
}

/// Transcreve um arquivo de áudio já gravado (para gravações antigas sem transcrição).
enum TranscriptionService {
    static func transcribe(url: URL, localeId: String) async throws -> String {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscriptionError.notAuthorized }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        final class Once { var done = false }
        let once = Once()
        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if once.done { return }
                if let error {
                    once.done = true
                    cont.resume(throwing: error)
                } else if let result, result.isFinal {
                    once.done = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
