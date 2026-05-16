import Foundation

public enum OLMXClientError: Error, LocalizedError, Equatable {
    case invalidBaseURL
    case authenticationRequired
    case requestFailed(Int, String)
    case noChoices
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The OLMX base URL is not valid."
        case .authenticationRequired:
            return "The OLMX API key is missing or invalid."
        case .requestFailed(let status, let body):
            return "OLMX request failed with HTTP \(status): \(body)"
        case .noChoices:
            return "OLMX did not return a completion choice."
        case .emptyResponse:
            return "OLMX returned an empty response."
        }
    }
}

public final class OLMXClient: @unchecked Sendable {
    public var baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        decoder.keyDecodingStrategy = .useDefaultKeys
    }

    public convenience init(baseURLString: String, session: URLSession = .shared) throws {
        guard let url = URL(string: baseURLString) else {
            throw OLMXClientError.invalidBaseURL
        }
        self.init(baseURL: url, session: session)
    }

    public static func isConnectionRefused(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .cannotConnectToHost
            || urlError.code == .cannotFindHost
            || urlError.code == .notConnectedToInternet
    }

    public static func isRetryablePolishFailure(_ error: Error) -> Bool {
        if let clientError = error as? OLMXClientError {
            switch clientError {
            case .requestFailed, .authenticationRequired:
                return true
            case .invalidBaseURL, .noChoices, .emptyResponse:
                return false
            }
        }

        guard let urlError = error as? URLError else { return false }
        return urlError.code == .timedOut
            || urlError.code == .networkConnectionLost
            || urlError.code == .cannotLoadFromNetwork
    }

    public func health() async throws -> OLMXHealth {
        return try await health(apiKey: nil)
    }

    public func health(apiKey: String?) async throws -> OLMXHealth {
        let request = try makeRequest(path: "/health", apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(OLMXHealth.self, from: data)
    }

    public func models(apiKey: String) async throws -> [OLMXModel] {
        let request = try makeRequest(path: "/v1/models", apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        if let response = try? decoder.decode(ModelsResponse.self, from: data) {
            return response.data
        }

        let fallback = try decoder.decode([OLMXModel].self, from: data)
        return fallback
    }

    public func polish(
        transcript: String,
        persona: Persona,
        model: String,
        apiKey: String,
        temperature: Double = 0.1,
        maxTokens: Int = 900
    ) async throws -> String {
        var request = try makeRequest(path: "/v1/chat/completions", apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makePolishRequestBody(
            transcript: transcript,
            persona: persona,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
        #if DEBUG
        if let body = request.httpBody, let payload = String(data: body, encoding: .utf8) {
            print("PureVoice DEBUG OLMX /v1/chat/completions payload: \(payload)")
        }
        #endif

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let decoded = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OLMXClientError.noChoices
        }

        let trimmed = stripThinkingTokens(content, fallback: transcript)
        guard !trimmed.isEmpty else {
            throw OLMXClientError.emptyResponse
        }
        return enforceRewriteScope(trimmed, transcript: transcript)
    }

    public func makePolishRequestBody(
        transcript: String,
        persona: Persona,
        model: String,
        temperature: Double = 0.1,
        maxTokens: Int = 900
    ) throws -> Data {
        let userMessage = """
        You are an edit-only rewriting function. Rewrite only the dictated text inside <dictation> tags.

        Persona instructions:
        \(persona.systemPrompt)

        Hard constraints:
        - Preserve only the facts, asks, decisions, timeline, names, and intent present in the dictated text.
        - Do not add projects, people, deadlines, examples, subjects, greetings, closings, or any other context that is not present.
        - Do not continue the conversation or draft a new message from the topic.
        - If the dictated text is already short and clear, keep the polished output short.
        - Return ONLY the final polished text. Do not include a thinking process, analysis, explanation, options, drafts, markdown bullets, or numbered steps.

        <dictation>
        \(transcript)
        </dictation>
        """

        let request = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "user", content: userMessage)
            ],
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false,
            stop: ["\n---", "\n<dictation>", "\n</dictation>", "\n```", "<|endoftext|>"],
            enableThinking: false,
            thinking: false
        )
        return try encoder.encode(request)
    }

    private func stripThinkingTokens(_ text: String) -> String {
        stripThinkingTokens(text, fallback: nil)
    }

    private func stripThinkingTokens(_ text: String, fallback: String?) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")

        if let regex = try? NSRegularExpression(
            pattern: "<think>[\\s\\S]*?</think>",
            options: [.caseInsensitive]
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: ""
            )
        }

        if let extracted = extractFinalAnswerCandidate(from: result) {
            return extracted
        }

        let lines = result.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first, first.isNumber else { return true }
            let afterDigits = trimmed.drop(while: { $0.isNumber })
            return !afterDigits.hasPrefix(".")
        }

        let cleaned = filtered
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !isReasoningLine(trimmed)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if (cleaned.isEmpty || looksLikeReasoning(cleaned)), let fallback {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    private func extractFinalAnswerCandidate(from text: String) -> String? {
        if let candidate = extractCandidate(
            from: text,
            markerPattern: "(?im)^\\s*(?:[-*•]\\s*)?\\**\\s*(final polished text|final answer|final message|polished text|output|response)\\**\\s*[:：]"
        ) {
            return candidate
        }

        return extractCandidate(
            from: text,
            markerPattern: "(?im)^\\s*(?:[-*•]\\s*)?\\**\\s*option\\s*\\d+[^:：]*[:：]"
        )
    }

    private func extractCandidate(from text: String, markerPattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: markerPattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.matches(in: text, range: range).last,
              let markerRange = Range(match.range, in: text)
        else {
            return nil
        }

        let candidate = String(text[markerRange.upperBound...])
        let cleaned = cleanCandidate(candidate)
        return cleaned.isEmpty || looksLikeReasoning(cleaned) ? nil : cleaned
    }

    private func cleanCandidate(_ candidate: String) -> String {
        trimGeneratedContinuations(candidate)
            .components(separatedBy: "\n")
            .filter { !isReasoningLine($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`* "))
    }

    private func trimGeneratedContinuations(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")

        for marker in ["\n---", "\n<dictation>", "\n</dictation>", "\n```"] {
            if let range = result.range(of: marker, options: [.caseInsensitive]) {
                result = String(result[..<range.lowerBound])
            }
        }

        result = result
            .replacingOccurrences(of: "<dictation>", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "</dictation>", with: "", options: [.caseInsensitive])

        return result
    }

    private func enforceRewriteScope(_ candidate: String, transcript: String) -> String {
        let cleaned = cleanCandidate(candidate)
        guard !cleaned.isEmpty else {
            return normalizeTranscriptFallback(transcript)
        }

        let transcriptWords = wordCount(transcript)
        let outputWords = wordCount(cleaned)

        if transcriptWords <= 8, outputWords > transcriptWords + 16 {
            return normalizeTranscriptFallback(transcript)
        }

        if transcriptWords <= 24, outputWords > max(transcriptWords * 3, transcriptWords + 24) {
            return normalizeTranscriptFallback(transcript)
        }

        if transcriptWords >= 40, outputWords < max(8, transcriptWords / 3) {
            return normalizeTranscriptFallback(transcript)
        }

        return cleaned
    }

    private func wordCount(_ text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }

    private func normalizeTranscriptFallback(_ transcript: String) -> String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isReasoningLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        guard !lowered.isEmpty else { return false }

        if lowered.hasPrefix("here's a thinking process")
            || lowered.hasPrefix("thinking process")
            || lowered.hasPrefix("thought process")
            || lowered.hasPrefix("reasoning")
            || lowered.hasPrefix("analysis")
        {
            return true
        }

        let bulletPrefixes = ["-", "*", "•"]
        guard bulletPrefixes.contains(where: { lowered.hasPrefix($0) }) else {
            return false
        }

        return [
            "input",
            "instructions",
            "task",
            "constraints",
            "persona",
            "context",
            "intent",
            "content",
            "requirements",
            "rewrite",
            "remove",
            "return",
            "preserve"
        ].contains { lowered.contains($0) }
    }

    private func looksLikeReasoning(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("here's a thinking process")
            || lowered.hasPrefix("thinking process")
            || lowered.hasPrefix("thought process")
            || lowered.hasPrefix("reasoning")
            || lowered.hasPrefix("analysis")
    }

    private func makeRequest(path: String, apiKey: String?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw OLMXClientError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw OLMXClientError.authenticationRequired
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OLMXClientError.requestFailed(http.statusCode, body)
        }
    }
}

private struct ModelsResponse: Decodable {
    var data: [OLMXModel]

    enum CodingKeys: String, CodingKey {
        case data
        case models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([OLMXModel].self, forKey: .data)
            ?? container.decodeIfPresent([OLMXModel].self, forKey: .models)
            ?? []
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var temperature: Double
    var maxTokens: Int
    var stream: Bool
    var stop: [String]
    var enableThinking: Bool
    var thinking: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case stop
        case enableThinking = "enable_thinking"
        case thinking
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String
        }

        var message: Message
    }

    var choices: [Choice]
}
