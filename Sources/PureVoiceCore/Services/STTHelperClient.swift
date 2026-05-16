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

    private func runHelper(arguments: [String]) throws -> Data {
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            throw STTHelperError.helperMissing(helperURL.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", helperURL.path] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: output + errorOutput, encoding: .utf8) ?? "No helper output."
            throw STTHelperError.processFailed(process.terminationStatus, message)
        }

        return output
    }
}
