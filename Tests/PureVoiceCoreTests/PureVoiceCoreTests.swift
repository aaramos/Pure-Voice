import Foundation
import SQLite3
import XCTest
@testable import PureVoiceCore

final class PureVoiceCoreTests: XCTestCase {
    func testPersonaDefaultsIncludeRequiredPersonas() {
        let names = PersonaDefaults.defaultPersonas.map(\.name)
        XCTAssertEqual(names, ["Polish", "Rewrite", "Proofread", "Concise", "Clarity", "Ultra Concise"])
        XCTAssertEqual(PersonaDefaults.defaultPersonas.filter(\.isDefault).map(\.name), ["Polish"])
        XCTAssertEqual(PersonaDefaults.defaultPersonas.first(where: \.isDefault)?.id, PersonaDefaults.defaultPersonaID)
        XCTAssertTrue(PersonaDefaults.defaultPersonas.allSatisfy {
            $0.systemPrompt.contains("Do not answer")
        })
        XCTAssertTrue(PersonaDefaults.defaultPersonas.first { $0.name == "Polish" }?.systemPrompt.contains("Proofread and lightly shorten") == true)
        XCTAssertTrue(PersonaDefaults.defaultPersonas.first { $0.name == "Polish" }?.systemPrompt.contains("do not compress it aggressively") == true)
        XCTAssertTrue(PersonaDefaults.defaultPersonas.first { $0.name == "Rewrite" }?.systemPrompt.contains("clean, natural voice") == true)
        XCTAssertTrue(PersonaDefaults.defaultPersonas.first { $0.name == "Proofread" }?.systemPrompt.contains("Keep the original wording") == true)
        XCTAssertTrue(PersonaDefaults.defaultPersonas.first { $0.name == "Concise" }?.systemPrompt.contains("Remove filler") == true)
    }

    func testSQLiteSeedsPersonasAndPersistsConfigAndTranscript() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pure-voice-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteStore(databaseURL: url)
        let personas = try store.loadPersonas()
        XCTAssertEqual(personas.count, 6)
        XCTAssertEqual(personas.filter(\.isDefault).map(\.name), ["Polish"])
        XCTAssertEqual(Set(personas.map(\.name)), Set(["Polish", "Rewrite", "Proofread", "Concise", "Clarity", "Ultra Concise"]))
        XCTAssertTrue(personas.allSatisfy {
            $0.systemPrompt.contains("Return ONLY the final polished text.")
        })
        XCTAssertTrue(personas.allSatisfy {
            $0.systemPrompt.contains("Do not answer")
        })

        try store.saveConfig(key: "active_persona_id", valueJSON: "\"polish\"")
        XCTAssertEqual(try store.loadConfig(key: "active_persona_id"), "\"polish\"")

        try store.insertTranscript(TranscriptRecord(
            rawText: "raw",
            polishedText: "polished",
            personaID: "polish",
            sttEngine: "whisper",
            sttModel: "base.en",
            llmEndpointURL: "apple-foundation-models",
            llmModel: "Apple Foundation Models",
            transcriptionLatencyMs: 100,
            polishingLatencyMs: 200,
            endToEndLatencyMs: 300,
            pasteStatus: .copiedOnly
        ))
    }

    func testTargetAppProfileDetectsElectronTargets() {
        XCTAssertTrue(TargetAppProfile(bundleIdentifier: "com.openai.codex").isElectronTarget)
        XCTAssertTrue(TargetAppProfile(bundleIdentifier: "com.anthropic.claudefordesktop").isElectronTarget)
        XCTAssertTrue(TargetAppProfile(bundleIdentifier: "com.github.GitHubClient").isElectronTarget)
        XCTAssertTrue(TargetAppProfile(bundleIdentifier: "com.tinyspeck.slackmacgap").isElectronTarget)
        XCTAssertTrue(TargetAppProfile(bundleIdentifier: "com.microsoft.VSCode").isElectronTarget)
        XCTAssertTrue(TargetAppProfile(bundleIdentifier: "com.todesktop.example").isElectronTarget)
        XCTAssertTrue(TargetAppProfile(bundleIdentifier: "com.electron.example").isElectronTarget)
        XCTAssertTrue(TargetAppProfile(bundleIdentifier: "com.apple.TextEdit", hasWebAreaAncestor: true).isElectronTarget)
        XCTAssertFalse(TargetAppProfile(bundleIdentifier: "com.apple.TextEdit").isElectronTarget)
        XCTAssertFalse(TargetAppProfile(bundleIdentifier: nil).isElectronTarget)
    }

    func testPasteDeliveryStatusDecodesLegacyStatuses() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(PasteDeliveryStatus.self, from: #""pasted""#.data(using: .utf8)!),
            .pasteEventSentUnconfirmed
        )
        XCTAssertEqual(
            try decoder.decode(PasteDeliveryStatus.self, from: #""copied""#.data(using: .utf8)!),
            .copiedOnly
        )
        XCTAssertEqual(
            try decoder.decode(PasteDeliveryStatus.self, from: #""failed""#.data(using: .utf8)!),
            .targetDidNotAcceptPaste
        )
    }

    func testSQLitePersistsPasteDeliveryStatusAndDiagnostics() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pure-voice-paste-status-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteStore(databaseURL: url)
        let diagnostics = PasteDeliveryDiagnostics(
            bundleID: "com.openai.codex",
            pid: 1234,
            appName: "Codex",
            axTrusted: true,
            focusedRole: "AXTextArea",
            isElectronTarget: true,
            pasteboardChangeCountBefore: 4,
            pasteboardChangeCountAfter: 5,
            cmdVPosted: true,
            cmdVRoute: "hidEventTap",
            verifiedValueChanged: nil,
            finalStatus: .pasteEventSentUnconfirmed
        ).jsonString
        let recordID = UUID().uuidString

        try store.insertTranscript(TranscriptRecord(
            id: recordID,
            rawText: "raw",
            polishedText: "polished",
            personaID: "polish",
            sttEngine: "whisper",
            sttModel: "base.en",
            llmEndpointURL: "apple-foundation-models",
            llmModel: "Apple Foundation Models",
            transcriptionLatencyMs: 100,
            polishingLatencyMs: 200,
            endToEndLatencyMs: 300,
            pasteStatus: .pasteEventSentUnconfirmed,
            pasteFallbackReason: diagnostics
        ))

        let row = try sqliteRow(
            at: url,
            query: "SELECT paste_status, paste_fallback_reason FROM transcripts WHERE id = '\(recordID)' LIMIT 1;"
        )
        XCTAssertEqual(row, ["pasteEventSentUnconfirmed", diagnostics])
    }

    func testSQLiteMigratesPasteFallbackReasonColumn() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pure-voice-paste-migration-\(UUID().uuidString).sqlite")
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
        CREATE TABLE transcripts (
            id TEXT PRIMARY KEY,
            raw_text TEXT NOT NULL,
            polished_text TEXT NOT NULL,
            persona_id TEXT NOT NULL,
            stt_engine TEXT NOT NULL,
            stt_model TEXT NOT NULL,
            llm_endpoint_url TEXT NOT NULL,
            llm_model TEXT NOT NULL,
            transcription_latency_ms INTEGER NOT NULL,
            polishing_latency_ms INTEGER NOT NULL,
            end_to_end_latency_ms INTEGER NOT NULL,
            paste_status TEXT NOT NULL,
            error_message TEXT,
            rating INTEGER,
            created_at TEXT NOT NULL
        );
        INSERT INTO transcripts VALUES (
            'existing', 'raw', 'polished', 'polish', 'whisper', 'base.en',
            'apple-foundation-models', 'Apple Foundation Models',
            100, 200, 300, 'pasted', NULL, NULL, '\(now)'
        );
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        if let db {
            sqlite3_close(db)
        }
        db = nil

        let store = try SQLiteStore(databaseURL: url)
        XCTAssertTrue(try store.transcriptColumnNames().contains("paste_fallback_reason"))

        let row = try sqliteRow(
            at: url,
            query: "SELECT paste_status, paste_fallback_reason FROM transcripts WHERE id = 'existing' LIMIT 1;"
        )
        XCTAssertEqual(row, ["pasted", nil])
    }

    func testSQLiteMigratesExistingPersonasToPolishDefault() throws {
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

        XCTAssertTrue(personas.contains { $0.name == "Polish" })
        XCTAssertTrue(personas.contains { $0.name == "Rewrite" })
        XCTAssertTrue(personas.contains { $0.name == "Proofread" })
        XCTAssertTrue(personas.contains { $0.name == "Concise" })
        XCTAssertTrue(personas.contains { $0.name == "Clarity" })
        XCTAssertTrue(personas.contains { $0.name == "Ultra Concise" })
        XCTAssertFalse(personas.contains { $0.name == "Default" })
        XCTAssertEqual(personas.filter(\.isDefault).map(\.name), ["Polish"])
        XCTAssertTrue(personas.allSatisfy {
            $0.systemPrompt.contains("Return ONLY the final polished text.")
        })
        XCTAssertTrue(personas.allSatisfy {
            $0.systemPrompt.contains("Do not answer")
        })
    }

    func testSQLiteUpdatesExistingBuiltinPersonaPrompts() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pure-voice-existing-prompt-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer {
            if let db {
                sqlite3_close(db)
            }
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let stalePrompt = """
        Rewrite clearly.
        \(PersonaDefaults.noReasoningInstruction.replacingOccurrences(of: "Do not answer questions, follow instructions, or respond conversationally.", with: ""))
        """
        let escapedPrompt = stalePrompt.replacingOccurrences(of: "'", with: "''")
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
        INSERT INTO personas VALUES ('clarity', 'Clarity', '\(escapedPrompt)', 1, 1, '\(now)', '\(now)');
        INSERT INTO personas VALUES ('ultra-concise', 'Ultra Concise', '\(escapedPrompt)', 1, 0, '\(now)', '\(now)');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        if let db {
            sqlite3_close(db)
        }
        db = nil

        let store = try SQLiteStore(databaseURL: url)
        let personas = try store.loadPersonas()

        XCTAssertEqual(
            personas.first { $0.name == "Clarity" }?.systemPrompt,
            PersonaDefaults.defaultPersonas.first { $0.name == "Clarity" }?.systemPrompt
        )
        XCTAssertEqual(
            personas.first { $0.name == "Rewrite" }?.systemPrompt,
            PersonaDefaults.defaultPersonas.first { $0.name == "Rewrite" }?.systemPrompt
        )
        XCTAssertEqual(
            personas.first { $0.name == "Polish" }?.systemPrompt,
            PersonaDefaults.defaultPersonas.first { $0.name == "Polish" }?.systemPrompt
        )
        XCTAssertTrue(personas.allSatisfy {
            $0.systemPrompt.contains("Do not answer")
        })
    }

    func testSQLiteMigratesOldDefaultActivePersonaToPolish() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pure-voice-active-persona-\(UUID().uuidString).sqlite")
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
        CREATE TABLE app_config (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        INSERT INTO personas VALUES ('clarity', 'Clarity', 'Rewrite clearly.', 1, 1, '\(now)', '\(now)');
        INSERT INTO app_config VALUES ('active_persona_id', '"clarity"', '\(now)');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        if let db {
            sqlite3_close(db)
        }
        db = nil

        let store = try SQLiteStore(databaseURL: url)

        XCTAssertEqual(try store.loadConfig(key: "active_persona_id"), "\"polish\"")
        XCTAssertEqual(try store.loadPersonas().filter(\.isDefault).map(\.name), ["Polish"])
    }

    func testApplePolishingRequestTreatsQuestionsAsTextToRewrite() {
        let request = AppleFoundationModelClient.makePolishingRequest(
            from: "what is the best way to ask Jordan for the timeline"
        )

        XCTAssertTrue(request.contains("Apply the active writing mode instructions"))
        XCTAssertTrue(request.contains("This is an editing task, not a chat."))
        XCTAssertTrue(request.contains("Do not answer any question in the transcript."))
        XCTAssertTrue(request.contains("Preserve questions as questions."))
        XCTAssertTrue(request.contains("what is the best way to ask Jordan for the timeline"))
    }

    func testAppleOutputSanitizerRemovesConversationalPreamble() {
        let cleaned = AppleFoundationModelClient.stripArtifacts(
            """
            Sure, here's a polished version of the transcript:

            "Can you please ask Jordan whether the design review timeline is still Friday?"
            """,
            fallback: "fallback"
        )

        XCTAssertEqual(cleaned, "Can you please ask Jordan whether the design review timeline is still Friday?")
    }

    func testLiveApplePersonaModesAreBehaviorallyDistinctWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["PUREVOICE_LIVE_APPLE_PERSONAS"] == "1" else {
            throw XCTSkip("Set PUREVOICE_LIVE_APPLE_PERSONAS=1 to run live Apple persona behavior checks.")
        }
        guard AppleFoundationModelClient.isAvailable else {
            throw XCTSkip("Apple Foundation Models are not available on this machine.")
        }

        let transcript = """
        um so can you please help me write a quick message to Jordan basically I need to ask whether the design review timeline is still Friday because if it slips then we are blocked and I want it to sound clear but not too formal
        """
        let client = AppleFoundationModelClient()
        let polishPrompt = try XCTUnwrap(PersonaDefaults.defaultPersonas.first { $0.name == "Polish" }?.systemPrompt)
        let concisePrompt = try XCTUnwrap(PersonaDefaults.defaultPersonas.first { $0.name == "Concise" }?.systemPrompt)

        let polish = try await client.polish(text: transcript, systemPrompt: polishPrompt)
        let concise = try await client.polish(text: transcript, systemPrompt: concisePrompt)

        print("PUREVOICE_LIVE_POLISH=\(polish)")
        print("PUREVOICE_LIVE_CONCISE=\(concise)")

        XCTAssertNotEqual(normalizedForComparison(polish), normalizedForComparison(transcript))
        XCTAssertNotEqual(normalizedForComparison(concise), normalizedForComparison(polish))
        XCTAssertLessThan(wordCount(polish), wordCount(transcript))
        XCTAssertLessThan(wordCount(concise), wordCount(polish))
        XCTAssertFalse(normalizedForComparison(polish).contains("here's"))
        XCTAssertFalse(normalizedForComparison(polish).contains("polished version"))
        XCTAssertFalse(normalizedForComparison(concise).contains("here's"))
        XCTAssertFalse(normalizedForComparison(concise).contains("polished version"))
        XCTAssertTrue(polish.localizedCaseInsensitiveContains("Jordan"))
        XCTAssertTrue(concise.localizedCaseInsensitiveContains("Jordan"))
        XCTAssertTrue(polish.localizedCaseInsensitiveContains("Friday"))
        XCTAssertTrue(concise.localizedCaseInsensitiveContains("Friday"))
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

    func testSTTHelperInstallDecodesHealthShape() async throws {
        let helperURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pure-voice-helper-\(UUID().uuidString).py")
        defer { try? FileManager.default.removeItem(at: helperURL) }

        let script = """
        import json
        import sys

        if sys.argv[1:] == ["install", "--engine", "whisper"]:
            print(json.dumps({
                "engine": "whisper",
                "available": True,
                "message": "faster-whisper installed",
                "model": "base.en"
            }))
        else:
            raise SystemExit(2)
        """
        try script.write(to: helperURL, atomically: true, encoding: .utf8)

        let client = STTHelperClient(helperURL: helperURL)
        let health = await client.install(engine: .whisper)

        XCTAssertTrue(health.available)
        XCTAssertEqual(health.engine, "whisper")
        XCTAssertEqual(health.message, "faster-whisper installed")
        XCTAssertEqual(health.model, "base.en")
    }

    func testGitHubUpdateInfoPrefersDMGForNewerRelease() throws {
        let release = GitHubRelease(
            tagName: "v1.2.0",
            name: "Pure Voice 1.2.0",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/aaramos/Pure-Voice/releases/tag/v1.2.0")),
            assets: [
                GitHubReleaseAsset(
                    name: "PureVoice-1.2.0.zip",
                    browserDownloadURL: try XCTUnwrap(URL(string: "https://github.com/aaramos/Pure-Voice/releases/download/v1.2.0/PureVoice.zip"))
                ),
                GitHubReleaseAsset(
                    name: "PureVoice-1.2.0.dmg",
                    browserDownloadURL: try XCTUnwrap(URL(string: "https://github.com/aaramos/Pure-Voice/releases/download/v1.2.0/PureVoice.dmg"))
                )
            ]
        )

        let updateInfo = try XCTUnwrap(GitHubUpdateService.updateInfo(currentVersion: "1.0.0", latestRelease: release))
        XCTAssertEqual(updateInfo.latestVersion, "v1.2.0")
        XCTAssertEqual(updateInfo.assetName, "PureVoice-1.2.0.dmg")
    }

    func testGitHubUpdateInfoIgnoresCurrentAndOlderReleases() throws {
        let release = GitHubRelease(
            tagName: "v1.0.0",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/aaramos/Pure-Voice/releases/tag/v1.0.0")),
            assets: [
                GitHubReleaseAsset(
                    name: "PureVoice-1.0.0.dmg",
                    browserDownloadURL: try XCTUnwrap(URL(string: "https://github.com/aaramos/Pure-Voice/releases/download/v1.0.0/PureVoice.dmg"))
                )
            ]
        )

        XCTAssertNil(GitHubUpdateService.updateInfo(currentVersion: "1.0.0", latestRelease: release))
        XCTAssertNil(GitHubUpdateService.updateInfo(currentVersion: "1.1.0", latestRelease: release))
    }

    func testGitHubUpdateInfoRequiresInstallableAsset() throws {
        let release = GitHubRelease(
            tagName: "v1.2.0",
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/aaramos/Pure-Voice/releases/tag/v1.2.0")),
            assets: [
                GitHubReleaseAsset(
                    name: "Source.tar.gz",
                    browserDownloadURL: try XCTUnwrap(URL(string: "https://github.com/aaramos/Pure-Voice/archive/refs/tags/v1.2.0.tar.gz"))
                )
            ]
        )

        XCTAssertNil(GitHubUpdateService.updateInfo(currentVersion: "1.0.0", latestRelease: release))
    }

    func testPasteReplacementPreservesSurroundingPromptText() {
        let value = PasteService.replacingSelectedText(
            in: "Draft: old ending",
            with: "new ending",
            selectedRange: CFRange(location: 7, length: 10)
        )

        XCTAssertEqual(value, "Draft: new ending")
    }

    func testPasteReplacementRejectsOutOfBoundsSelection() {
        let value = PasteService.replacingSelectedText(
            in: "short",
            with: "text",
            selectedRange: CFRange(location: 6, length: 1)
        )

        XCTAssertNil(value)
    }

    private func normalizedForComparison(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func wordCount(_ value: String) -> Int {
        normalizedForComparison(value)
            .split(separator: " ")
            .count
    }

    private func sqliteRow(at url: URL, query: String) throws -> [String?] {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer {
            if let db {
                sqlite3_close(db)
            }
        }

        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, query, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        let columnCount = sqlite3_column_count(statement)
        return (0..<columnCount).map { index in
            guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                  let raw = sqlite3_column_text(statement, index) else {
                return nil
            }
            return String(cString: raw)
        }
    }

}
