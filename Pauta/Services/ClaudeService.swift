import Foundation

enum ClaudeError: LocalizedError {
    case missingKey
    case http(Int, String)
    case refused
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Configure sua chave de API do Claude em Ajustes."
        case .http(let code, let message):
            return "Erro da API (\(code)): \(message)"
        case .refused:
            return "O modelo recusou esta solicitação."
        case .invalidResponse:
            return "Resposta inválida da API."
        }
    }
}

/// Cliente mínimo da API do Claude (POST /v1/messages) via HTTP puro.
enum ClaudeService {
    static let apiKeyKeychainKey = "anthropic-api-key"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Chamada com streaming SSE — o texto chega aos poucos via `onDelta`.
    static func streamCompletion(system: String,
                                 user: String,
                                 model: String,
                                 apiKey: String,
                                 maxTokens: Int = 16000,
                                 useFallbacks: Bool = true,
                                 onDelta: @escaping @Sendable (String) -> Void) async throws -> String {
        let request = try makeRequest(system: system, user: user, model: model, apiKey: apiKey,
                                      maxTokens: maxTokens, stream: true, useFallbacks: useFallbacks)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }

        guard http.statusCode == 200 else {
            var body = ""
            for try await line in bytes.lines {
                body += line
            }
            let message = errorMessage(from: body)
            // Se a conta não aceitar o parâmetro de fallback (beta), tenta de novo sem ele.
            if http.statusCode == 400, useFallbacks, message.lowercased().contains("fallback") {
                return try await streamCompletion(system: system, user: user, model: model, apiKey: apiKey,
                                                  maxTokens: maxTokens, useFallbacks: false, onDelta: onDelta)
            }
            throw ClaudeError.http(http.statusCode, message)
        }

        var text = ""
        var stopReason: String?
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let piece = delta["text"] as? String {
                    text += piece
                    onDelta(piece)
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any],
                   let stop = delta["stop_reason"] as? String {
                    stopReason = stop
                }
            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String ?? "erro desconhecido"
                throw ClaudeError.http(http.statusCode, message)
            default:
                break
            }
        }

        if stopReason == "refusal" { throw ClaudeError.refused }
        guard !text.isEmpty else { throw ClaudeError.invalidResponse }
        return text
    }

    /// Chamada curta sem streaming (ex.: sugerir título).
    static func complete(system: String,
                         user: String,
                         model: String,
                         apiKey: String,
                         maxTokens: Int = 300) async throws -> String {
        let request = try makeRequest(system: system, user: user, model: model, apiKey: apiKey,
                                      maxTokens: maxTokens, stream: false, useFallbacks: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }
        guard http.statusCode == 200 else {
            throw ClaudeError.http(http.statusCode, errorMessage(from: String(data: data, encoding: .utf8) ?? ""))
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ClaudeError.invalidResponse
        }
        if object["stop_reason"] as? String == "refusal" { throw ClaudeError.refused }
        let blocks = object["content"] as? [[String: Any]] ?? []
        let text = blocks
            .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined()
        guard !text.isEmpty else { throw ClaudeError.invalidResponse }
        return text
    }

    private static func makeRequest(system: String,
                                    user: String,
                                    model: String,
                                    apiKey: String,
                                    maxTokens: Int,
                                    stream: Bool,
                                    useFallbacks: Bool) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        if stream { body["stream"] = true }

        // Fallback de recusa server-side, recomendado para os modelos Opus 5 / Fable 5.
        let wantsFallbacks = useFallbacks && (model.contains("opus-5") || model.contains("fable-5"))
        if wantsFallbacks { body["fallbacks"] = "default" }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if wantsFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func errorMessage(from body: String) -> String {
        if let data = body.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return body.isEmpty ? "sem detalhes" : String(body.prefix(300))
    }
}
