import Foundation
import XCTest
@testable import PureVoiceCore

final class PureVoiceCoreTests: XCTestCase {
    func testPersonaDefaultsIncludeRequiredPersonas() {
        let names = Set(PersonaDefaults.defaultPersonas.map(\.name))
        XCTAssertTrue(names.contains("Default"))
        XCTAssertTrue(names.contains("Professional"))
        XCTAssertTrue(names.contains("Casual Friend"))
        XCTAssertTrue(names.contains("Boss"))
        XCTAssertTrue(names.contains("Technical"))
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
        let messages = object?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["role"], "system")
        XCTAssertEqual(messages?.first?["content"], persona.systemPrompt)
        XCTAssertTrue(messages?.last?["content"]?.contains("ship this tomorrow") == true)
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
        XCTAssertEqual(try store.loadPersonas().count, 5)

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

        try store.save("secret")
        XCTAssertEqual(try store.read(), "secret")

        try store.save("updated")
        XCTAssertEqual(try store.read(), "updated")

        try store.delete()
        XCTAssertNil(try store.read())
    }
}
