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
        temperature: Double = 0.25,
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

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let decoded = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OLMXClientError.noChoices
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OLMXClientError.emptyResponse
        }
        return trimmed
    }

    public func makePolishRequestBody(
        transcript: String,
        persona: Persona,
        model: String,
        temperature: Double = 0.25,
        maxTokens: Int = 900
    ) throws -> Data {
        let request = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: persona.systemPrompt),
                .init(
                    role: "user",
                    content: """
                    Polish the following dictated text for the selected persona. Preserve facts, asks, decisions, and intent. Remove filler and repetition. Return only the final polished text.

                    Dictated text:
                    \(transcript)
                    """
                )
            ],
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )
        return try encoder.encode(request)
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

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
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
