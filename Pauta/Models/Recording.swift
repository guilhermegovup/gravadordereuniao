import Foundation
import SwiftData

@Model
final class Recording {
    var id: UUID = UUID()
    var title: String = "Nova gravação"
    var createdAt: Date = Date.now
    var duration: TimeInterval = 0
    var audioFileName: String = ""
    var transcript: String = ""
    var transcriptLocale: String = ""
    var summary: String = ""
    var summaryTemplateRaw: String = ""
    var notes: String = ""

    init(title: String,
         createdAt: Date = .now,
         duration: TimeInterval,
         audioFileName: String,
         transcript: String = "",
         transcriptLocale: String = "") {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.transcript = transcript
        self.transcriptLocale = transcriptLocale
    }

    var audioURL: URL? {
        guard !audioFileName.isEmpty else { return nil }
        let url = AudioStore.url(for: audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// Onde os arquivos de áudio ficam guardados (Application Support/Recordings).
enum AudioStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func newFile() -> (url: URL, name: String) {
        let name = UUID().uuidString + ".m4a"
        return (url(for: name), name)
    }

    static func delete(_ name: String) {
        guard !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }
}

enum TimeFormat {
    static func string(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
