import Foundation
import SQLite3
import XCTest
@testable import PureVoiceCore

final class PureVoiceCoreTests: XCTestCase {
    func testPersonaDefaultsIncludeRequiredPersonas() {
        let names = Set(PersonaDefaults.defaultPersonas.map(\.name))
        XCTAssertTrue(names.contains("Clarity"))
        XCTAssertTrue(names.contains("Ultra Concise"))
        XCTAssertTrue(names.contains("Default"))
        XCTAssertTrue(names.contains("Professional"))
        XCTAssertTrue(names.contains("Casual Friend"))
        XCTAssertTrue(names.contains("Boss"))
        XCTAssertTrue(names.contains("Technical"))
        XCTAssertEqual(PersonaDefaults.defaultPersonas.filter(\.isDefault).map(\.name), ["Clarity"])
    }

    func testOLMXPolishRequestContainsPersonaAndTranscript() throws {
        let client = try OLMXClient(baseURLString: "http://127.0.0.1:8000")
        let persona = PersonaDefaults.defaultPersonas[0]
        let data = try client.makePolishRequestBody(
            transcript: "um I think we should ship this tomorrow",
            persona: persona,
            model: "test-model"
        )

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["model"] as? String, "test-model")
        XCTAssertEqual(object?["stream"] as? Bool, false)
        XCTAssertEqual(object?["enable_thinking"] as? Bool, false)
        XCTAssertEqual(object?["thinking"] as? Bool, false)
        XCTAssertTrue((object?["stop"] as? [String])?.contains("\n<dictation>") == true)
        let messages = object?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertTrue(messages?.first?["content"]?.contains("Persona instructions:") == true)
        XCTAssertTrue(messages?.first?["content"]?.contains("Do not add projects") == true)
        XCTAssertTrue(messages?.first?["content"]?.contains("<dictation>") == true)
        XCTAssertTrue(messages?.first?["content"]?.contains(persona.systemPrompt) == true)
        XCTAssertTrue(messages?.first?["content"]?.contains("ship this tomorrow") == true)
    }

    func testOLMXPolishStripsThinkingBlocksAndNumberedReasoning() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = """
            {
              "choices": [
                {
                  "message": {
                    "content": "<think>private scratchpad</think>\\n1. Analyze the input.\\n2. Draft a reply.\\nGood morning! Hope your day is off to a great start."
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            return (response, data)
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OLMXClient(baseURL: URL(string: "http://127.0.0.1:8000")!, session: session)

        let polished = try await client.polish(
            transcript: "Good morning",
            persona: PersonaDefaults.defaultPersonas.first { $0.name == "Casual Friend" }!,
            model: "Qwen3.6-27B-8bit",
            apiKey: "test-key"
        )

        XCTAssertEqual(polished, "Good morning! Hope your day is off to a great start.")
    }

    func testOLMXPolishFallsBackWhenShortInputHallucinatesLongContent() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = """
            {
              "choices": [
                {
                  "message": {
                    "content": "Good morning,\\n\\nRegarding the project timeline, I found a blocker with legal review and need a decision by tomorrow at 3 PM."
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            return (response, data)
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OLMXClient(baseURL: URL(string: "http://127.0.0.1:8000")!, session: session)

        let polished = try await client.polish(
            transcript: "Good morning",
            persona: PersonaDefaults.defaultPersonas.first { $0.name == "Professional" }!,
            model: "Mistral-7B-Instruct-v0.3-4bit",
            apiKey: "test-key"
        )

        XCTAssertEqual(polished, "Good morning")
    }

    func testOLMXPolishTrimsGeneratedDictationContinuation() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = """
            {
              "choices": [
                {
                  "message": {
                    "content": "Good morning!\\n\\n---\\n\\n<dictation>\\nInvented follow-up\\n</dictation>"
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            return (response, data)
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OLMXClient(baseURL: URL(string: "http://127.0.0.1:8000")!, session: session)

        let polished = try await client.polish(
            transcript: "Good morning",
            persona: PersonaDefaults.defaultPersonas.first { $0.name == "Casual Friend" }!,
            model: "Mistral-7B-Instruct-v0.3-4bit",
            apiKey: "test-key"
        )

        XCTAssertEqual(polished, "Good morning!")
    }

    func testOLMXPolishExtractsOptionFromThinkingProcessLeak() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = """
            {
              "choices": [
                {
                  "message": {
                    "content": "Thinking Process:\\n* **Input:** Good morning\\n* **Task:** Make it warm.\\n* **Option 1 (Literal):** Good morning!\\n* **Option 2 (Warm/Friendly):** Good morning! Hope your day is off to a great start."
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            return (response, data)
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OLMXClient(baseURL: URL(string: "http://127.0.0.1:8000")!, session: session)

        let polished = try await client.polish(
            transcript: "Good morning",
            persona: PersonaDefaults.defaultPersonas.first { $0.name == "Casual Friend" }!,
            model: "Qwen3.6-27B-8bit",
            apiKey: "test-key"
        )

        XCTAssertEqual(polished, "Good morning! Hope your day is off to a great start.")
    }

    func testOLMXPolishExtractsMarkdownFinalPolishedTextMarker() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = """
            {
              "choices": [
                {
                  "message": {
                    "content": "Good morning.\\n\\n### Final Polished Text:\\nGood morning."
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            return (response, data)
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OLMXClient(baseURL: URL(string: "http://127.0.0.1:8000")!, session: session)

        let polished = try await client.polish(
            transcript: "Good morning",
            persona: PersonaDefaults.defaultPersonas.first { $0.name == "Professional" }!,
            model: "Phi-3.5-mini-instruct-4bit",
            apiKey: "test-key"
        )

        XCTAssertEqual(polished, "Good morning.")
    }

    func testOLMXPolishKeepsMultilineCandidateAfterOptionMarker() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = """
            {
              "choices": [
                {
                  "message": {
                    "content": "Thinking Process:\\n* **Input:** longer dictation\\n* **Task:** make it friendly.\\n* **Option 1 (Warm/Friendly):** Good morning! Hope you’re doing well. Just a quick heads-up: don’t fly with a big, unlabeled bag of ashes. My sisters and I divided them up, and I tossed a large ziplock into my carry-on without thinking. Needless to say, I triggered bomb and gunpowder protocol, lol."
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            return (response, data)
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OLMXClient(baseURL: URL(string: "http://127.0.0.1:8000")!, session: session)

        let polished = try await client.polish(
            transcript: "Good morning, heads up to not fly with the big unlabeled bag of ashes. My sisters and I divided them up, and I tossed a large ziplock into my carry-on without thinking. Needless to say, I triggered bomb and gunpowder protocol.",
            persona: PersonaDefaults.defaultPersonas.first { $0.name == "Casual Friend" }!,
            model: "Qwen3.6-27B-8bit",
            apiKey: "test-key"
        )

        XCTAssertTrue(polished.contains("My sisters and I divided them up"))
        XCTAssertTrue(polished.contains("gunpowder protocol"))
        XCTAssertFalse(polished.hasSuffix(" My"))
    }

    func testLiveOLMXPolishForAllDefaultPersonasWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["PUREVOICE_LIVE_OLMX"] == "1" else {
            throw XCTSkip("Set PUREVOICE_LIVE_OLMX=1 to run the local OLMX persona smoke test.")
        }

        let apiKey = try XCTUnwrap(try KeychainStore().read()?.trimmingCharacters(in: .whitespacesAndNewlines))
        let model = Self.activeOLMXModelFromDefaults() ?? "Qwen3.6-27B-8bit"
        let client = try OLMXClient(baseURLString: "http://127.0.0.1:8000")

        for persona in PersonaDefaults.defaultPersonas {
            let polished = try await client.polish(
                transcript: "Good morning",
                persona: persona,
                model: model,
                apiKey: apiKey,
                maxTokens: 80
            )

            print("PureVoice live OLMX smoke \(persona.name): \(polished.prefix(600))")

            XCTAssertFalse(polished.localizedCaseInsensitiveContains("<think>"), persona.name)
            XCTAssertFalse(polished.localizedCaseInsensitiveContains("analyze"), persona.name)
            XCTAssertFalse(polished.localizedCaseInsensitiveContains("reasoning"), persona.name)
            XCTAssertFalse(polished.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let first = trimmed.first, first.isNumber else { return false }
                return trimmed.drop(while: { $0.isNumber }).hasPrefix(".")
            }, persona.name)
            XCTAssertFalse(polished.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•")
            }, persona.name)
            XCTAssertFalse(polished.isEmpty, persona.name)
            XCTAssertLessThan(polished.count, 240, persona.name)
        }
    }

    private static func activeOLMXModelFromDefaults() -> String? {
        let domains = ["com.adrian.purevoice", "com.adrian.PureVoice"]
        for domain in domains {
            if let value = UserDefaults.standard.persistentDomain(forName: domain)?["selectedOLMXModel"] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    func testOLMXPolishRetryPolicyClassifiesExpectedFailures() {
        XCTAssertTrue(OLMXClient.isRetryablePolishFailure(OLMXClientError.requestFailed(503, "warming")))
        XCTAssertTrue(OLMXClient.isRetryablePolishFailure(OLMXClientError.authenticationRequired))
        XCTAssertTrue(OLMXClient.isRetryablePolishFailure(URLError(.timedOut)))

        XCTAssertTrue(OLMXClient.isConnectionRefused(URLError(.cannotConnectToHost)))
        XCTAssertFalse(OLMXClient.isRetryablePolishFailure(URLError(.cannotConnectToHost)))
        XCTAssertFalse(OLMXClient.isRetryablePolishFailure(OLMXClientError.emptyResponse))
    }

    func testSQLiteSeedsPersonasAndPersistsConfigAndTranscript() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pure-voice-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteStore(databaseURL: url)
        let personas = try store.loadPersonas()
        XCTAssertEqual(personas.count, 7)
        XCTAssertEqual(personas.filter(\.isDefault).map(\.name), ["Clarity"])
        XCTAssertTrue(personas.allSatisfy {
            $0.systemPrompt.contains("Return ONLY the final polished text.")
        })

        try store.saveConfig(key: "selected_llm_model", valueJSON: "\"model-a\"")
        XCTAssertEqual(try store.loadConfig(key: "selected_llm_model"), "\"model-a\"")

        try store.insertTranscript(TranscriptRecord(
            rawText: "raw",
            polishedText: "polished",
            personaID: "default",
            sttEngine: "whisper",
            sttModel: "base.en",
            llmEndpointURL: "http://127.0.0.1:8000",
            llmModel: "model-a",
            transcriptionLatencyMs: 100,
            polishingLatencyMs: 200,
            endToEndLatencyMs: 300,
            pasteStatus: .copied
        ))
    }

    func testSQLiteMigratesExistingPersonasToClarityDefault() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pure-voice-existing-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer {
            if let db {
                sqlite3_close(db)
            }
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
        CREATE TABLE personas (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            system_prompt TEXT NOT NULL,
            is_builtin INTEGER NOT NULL,
            is_default INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        INSERT INTO personas VALUES ('default', 'Default', 'Rewrite clearly.', 1, 1, '\(now)', '\(now)');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        if let db {
            sqlite3_close(db)
        }
        db = nil

        let store = try SQLiteStore(databaseURL: url)
        let personas = try store.loadPersonas()

        XCTAssertTrue(personas.contains { $0.name == "Clarity" })
        XCTAssertTrue(personas.contains { $0.name == "Ultra Concise" })
        XCTAssertEqual(personas.filter(\.isDefault).map(\.name), ["Clarity"])
        XCTAssertTrue(personas.allSatisfy {
            $0.systemPrompt.contains("Return ONLY the final polished text.")
        })
    }

    func testSTTResultDecodesHelperShape() throws {
        let json = """
        {
          "engine": "whisper",
          "model": "base.en",
          "raw_text": "hello there",
          "latency_ms": 123,
          "status": "ok",
          "error_message": null
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(STTResult.self, from: json)
        XCTAssertEqual(result.engine, "whisper")
        XCTAssertEqual(result.model, "base.en")
        XCTAssertEqual(result.rawText, "hello there")
        XCTAssertEqual(result.latencyMs, 123)
    }

    func testKeychainRoundTrip() throws {
        let store = KeychainStore(service: "com.adrian.purevoice.tests.\(UUID().uuidString)", account: "api-key")
        defer { try? store.delete() }

        XCTAssertFalse(store.containsValueWithoutUserInteraction())

        try store.save("secret")
        XCTAssertTrue(store.containsValueWithoutUserInteraction())
        XCTAssertEqual(try store.read(), "secret")
        XCTAssertEqual(try store.read(allowsUserInteraction: false), "secret")

        try store.save("updated")
        XCTAssertEqual(try store.read(), "updated")

        try store.delete()
        XCTAssertFalse(store.containsValueWithoutUserInteraction())
        XCTAssertNil(try store.read())
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }

            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
