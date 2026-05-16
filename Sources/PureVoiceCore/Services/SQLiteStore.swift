import Foundation
import SQLite3

public enum SQLiteStoreError: Error, LocalizedError, Equatable {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): "Could not open the Pure Voice database: \(message)"
        case .executeFailed(let message): "Could not update the Pure Voice database: \(message)"
        case .prepareFailed(let message): "Could not prepare the Pure Voice database statement: \(message)"
        case .stepFailed(let message): "Could not read the Pure Voice database statement: \(message)"
        }
    }
}

public final class SQLiteStore: @unchecked Sendable {
    private let databaseURL: URL
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let dateFormatter = ISO8601DateFormatter()

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw SQLiteStoreError.openFailed(lastErrorMessage)
        }
        try initialize()
    }

    deinit {
        sqlite3_close(db)
    }

    public static func defaultDatabaseURL() throws -> URL {
        let directory = try applicationSupportDirectory()
        return directory.appendingPathComponent("pure_voice.sqlite")
    }

    public static func applicationSupportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Pure Voice", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func initialize() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS personas (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            system_prompt TEXT NOT NULL,
            is_builtin INTEGER NOT NULL,
            is_default INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS transcripts (
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

        CREATE TABLE IF NOT EXISTS app_config (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS model_cache (
            id TEXT PRIMARY KEY,
            endpoint_url TEXT NOT NULL,
            model_id TEXT NOT NULL,
            display_name TEXT,
            provider TEXT,
            last_seen_at TEXT NOT NULL
        );
        """)
        try seedDefaultPersonasIfNeeded()
    }

    public func seedDefaultPersonasIfNeeded() throws {
        if try !loadPersonas().isEmpty {
            return
        }

        for persona in PersonaDefaults.defaultPersonas {
            try upsertPersona(persona)
        }
    }

    public func loadPersonas() throws -> [Persona] {
        try locked {
            let statement = try prepare("""
            SELECT id, name, system_prompt, is_builtin, is_default, created_at, updated_at
            FROM personas
            ORDER BY is_default DESC, name ASC;
            """)
            defer { sqlite3_finalize(statement) }

            var personas: [Persona] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                personas.append(Persona(
                    id: columnText(statement, 0),
                    name: columnText(statement, 1),
                    systemPrompt: columnText(statement, 2),
                    isBuiltin: sqlite3_column_int(statement, 3) == 1,
                    isDefault: sqlite3_column_int(statement, 4) == 1,
                    createdAt: parseDate(columnText(statement, 5)),
                    updatedAt: parseDate(columnText(statement, 6))
                ))
            }
            return personas
        }
    }

    public func upsertPersona(_ persona: Persona) throws {
        try locked {
            let statement = try prepare("""
            INSERT INTO personas (id, name, system_prompt, is_builtin, is_default, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                system_prompt = excluded.system_prompt,
                is_builtin = excluded.is_builtin,
                is_default = excluded.is_default,
                updated_at = excluded.updated_at;
            """)
            defer { sqlite3_finalize(statement) }

            bindText(statement, 1, persona.id)
            bindText(statement, 2, persona.name)
            bindText(statement, 3, persona.systemPrompt)
            sqlite3_bind_int(statement, 4, persona.isBuiltin ? 1 : 0)
            sqlite3_bind_int(statement, 5, persona.isDefault ? 1 : 0)
            bindText(statement, 6, formatDate(persona.createdAt))
            bindText(statement, 7, formatDate(persona.updatedAt))

            try stepDone(statement)
        }
    }

    public func saveConfig(key: String, valueJSON: String) throws {
        try locked {
            let statement = try prepare("""
            INSERT INTO app_config (key, value_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                value_json = excluded.value_json,
                updated_at = excluded.updated_at;
            """)
            defer { sqlite3_finalize(statement) }

            bindText(statement, 1, key)
            bindText(statement, 2, valueJSON)
            bindText(statement, 3, formatDate(Date()))
            try stepDone(statement)
        }
    }

    public func loadConfig(key: String) throws -> String? {
        try locked {
            let statement = try prepare("SELECT value_json FROM app_config WHERE key = ? LIMIT 1;")
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, key)

            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                return columnText(statement, 0)
            }
            if step == SQLITE_DONE {
                return nil
            }
            throw SQLiteStoreError.stepFailed(lastErrorMessage)
        }
    }

    public func cacheModels(endpointURL: String, models: [OLMXModel]) throws {
        try locked {
            for model in models {
                let statement = try prepare("""
                INSERT INTO model_cache (id, endpoint_url, model_id, display_name, provider, last_seen_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    endpoint_url = excluded.endpoint_url,
                    model_id = excluded.model_id,
                    display_name = excluded.display_name,
                    provider = excluded.provider,
                    last_seen_at = excluded.last_seen_at;
                """)
                defer { sqlite3_finalize(statement) }
                let cacheID = "\(endpointURL)|\(model.id)"
                bindText(statement, 1, cacheID)
                bindText(statement, 2, endpointURL)
                bindText(statement, 3, model.id)
                bindText(statement, 4, model.id)
                bindText(statement, 5, model.ownedBy)
                bindText(statement, 6, formatDate(Date()))
                try stepDone(statement)
            }
        }
    }

    public func insertTranscript(_ record: TranscriptRecord) throws {
        try locked {
            let statement = try prepare("""
            INSERT INTO transcripts (
                id, raw_text, polished_text, persona_id, stt_engine, stt_model, llm_endpoint_url,
                llm_model, transcription_latency_ms, polishing_latency_ms, end_to_end_latency_ms,
                paste_status, error_message, rating, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
            defer { sqlite3_finalize(statement) }

            bindText(statement, 1, record.id)
            bindText(statement, 2, record.rawText)
            bindText(statement, 3, record.polishedText)
            bindText(statement, 4, record.personaID)
            bindText(statement, 5, record.sttEngine)
            bindText(statement, 6, record.sttModel)
            bindText(statement, 7, record.llmEndpointURL)
            bindText(statement, 8, record.llmModel)
            sqlite3_bind_int(statement, 9, Int32(record.transcriptionLatencyMs))
            sqlite3_bind_int(statement, 10, Int32(record.polishingLatencyMs))
            sqlite3_bind_int(statement, 11, Int32(record.endToEndLatencyMs))
            bindText(statement, 12, record.pasteStatus.rawValue)
            bindText(statement, 13, record.errorMessage)
            if let rating = record.rating {
                sqlite3_bind_int(statement, 14, Int32(rating))
            } else {
                sqlite3_bind_null(statement, 14)
            }
            bindText(statement, 15, formatDate(record.createdAt))

            try stepDone(statement)
        }
    }

    private func execute(_ sql: String) throws {
        try locked {
            var errorMessage: UnsafeMutablePointer<Int8>?
            let status = sqlite3_exec(db, sql, nil, nil, &errorMessage)
            if status != SQLITE_OK {
                let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
                sqlite3_free(errorMessage)
                throw SQLiteStoreError.executeFailed(message)
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(lastErrorMessage)
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(lastErrorMessage)
        }
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: pointer)
    }

    private func parseDate(_ value: String) -> Date {
        dateFormatter.date(from: value) ?? Date()
    }

    private func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private var lastErrorMessage: String {
        if let db {
            String(cString: sqlite3_errmsg(db))
        } else {
            "Unknown SQLite error."
        }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
