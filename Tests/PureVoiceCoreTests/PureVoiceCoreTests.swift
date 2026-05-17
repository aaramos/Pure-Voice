import Foundation
import SQLite3
import XCTest
@testable import PureVoiceCore

final class PureVoiceCoreTests: XCTestCase {
    func testPersonaDefaultsIncludeRequiredPersonas() {
        let names = PersonaDefaults.defaultPersonas.map(\.name)
        XCTAssertEqual(names, ["Clarity", "Ultra Concise"])
        XCTAssertEqual(PersonaDefaults.defaultPersonas.filter(\.isDefault).map(\.name), ["Clarity"])
    }

    func testSQLiteSeedsPersonasAndPersistsConfigAndTranscript() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pure-voice-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteStore(databaseURL: url)
        let personas = try store.loadPersonas()
        XCTAssertEqual(personas.count, 2)
        XCTAssertEqual(personas.filter(\.isDefault).map(\.name), ["Clarity"])
        XCTAssertEqual(Set(personas.map(\.name)), Set(["Clarity", "Ultra Concise"]))
        XCTAssertTrue(personas.allSatisfy {
            $0.systemPrompt.contains("Return ONLY the final polished text.")
        })

        try store.saveConfig(key: "active_persona_id", valueJSON: "\"clarity\"")
        XCTAssertEqual(try store.loadConfig(key: "active_persona_id"), "\"clarity\"")

        try store.insertTranscript(TranscriptRecord(
            rawText: "raw",
            polishedText: "polished",
            personaID: "clarity",
            sttEngine: "whisper",
            sttModel: "base.en",
            llmEndpointURL: "apple-foundation-models",
            llmModel: "Apple Foundation Models",
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
        XCTAssertFalse(personas.contains { $0.name == "Default" })
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

}
