import Foundation

public enum STTHelperError: Error, LocalizedError, Equatable {
    case helperMissing(String)
    case processFailed(Int32, String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .helperMissing(let path):
            return "STT helper was not found at \(path)."
        case .processFailed(let code, let message):
            return "STT helper failed with exit code \(code): \(message)"
        case .emptyTranscript:
            return "No speech was detected in the recording."
        }
    }
}

public final class STTHelperClient: @unchecked Sendable {
    private let helperURL: URL
    private let decoder = JSONDecoder()
    public typealias ProgressHandler = @Sendable (String) -> Void

    public init(helperURL: URL) {
        self.helperURL = helperURL
    }

    public func health(engine: STTEngine) async -> STTHealth {
        do {
            let data = try await Task.detached {
                try self.runHelper(arguments: ["health", "--engine", engine.rawValue])
            }.value
            return try decoder.decode(STTHealth.self, from: data)
        } catch {
            return STTHealth(
                engine: engine.rawValue,
                available: false,
                message: error.localizedDescription,
                model: nil
            )
        }
    }

    public func install(engine: STTEngine, onProgress: ProgressHandler? = nil) async -> STTHealth {
        do {
            let data = try await Task.detached {
                try self.runHelper(arguments: ["install", "--engine", engine.rawValue], onProgress: onProgress)
            }.value
            return try decoder.decode(STTHealth.self, from: data)
        } catch {
            return STTHealth(
                engine: engine.rawValue,
                available: false,
                message: error.localizedDescription,
                model: nil
            )
        }
    }

    public func transcribe(audioURL: URL, engine: STTEngine, model: String?) async throws -> STTResult {
        var arguments = [
            "transcribe",
            "--engine", engine.rawValue,
            "--audio", audioURL.path
        ]

        if let model, !model.isEmpty {
            arguments += ["--model", model]
        }

        let data = try await Task.detached {
            try self.runHelper(arguments: arguments)
        }.value
        let result = try decoder.decode(STTResult.self, from: data)
        let text = result.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == "ok" else {
            throw STTHelperError.processFailed(1, result.errorMessage ?? "Unknown transcription failure.")
        }
        guard !text.isEmpty else {
            throw STTHelperError.emptyTranscript
        }
        return result
    }

    private func runHelper(arguments: [String], onProgress: ProgressHandler? = nil) throws -> Data {
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            throw STTHelperError.helperMissing(helperURL.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", helperURL.path] + arguments
        process.environment = makeHelperEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let errorBuffer = LockedDataBuffer()
        if let onProgress {
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                errorBuffer.append(data)
                Self.emitProgress(from: data, onProgress: onProgress)
            }
        }
        defer {
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput: Data
        if onProgress == nil {
            errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        } else {
            errorOutput = errorBuffer.data()
        }

        guard process.terminationStatus == 0 else {
            let message = String(data: output + errorOutput, encoding: .utf8) ?? "No helper output."
            throw STTHelperError.processFailed(process.terminationStatus, message)
        }

        return output
    }

    private static func emitProgress(from data: Data, onProgress: ProgressHandler) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let payload = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let progress = object["progress"] as? String else {
                continue
            }
            onProgress(progress)
        }
    }

    private func makeHelperEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pure Voice/STT")
        let matplotlibConfig = appSupport.appendingPathComponent("matplotlib")
        try? FileManager.default.createDirectory(at: matplotlibConfig, withIntermediateDirectories: true)
        environment["MPLCONFIGDIR"] = matplotlibConfig.path
        return environment
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
