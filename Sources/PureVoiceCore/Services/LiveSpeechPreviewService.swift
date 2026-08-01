import AVFoundation
import Foundation
import Speech

public enum LiveSpeechPreviewError: Error, LocalizedError, Equatable {
    case authorizationDenied
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case inputUnavailable
    case audioEngineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition permission is needed for live text."
        case .recognizerUnavailable:
            return "Live speech recognition is not available right now."
        case .onDeviceRecognitionUnavailable:
            return "On-device live speech recognition is not available on this Mac."
        case .inputUnavailable:
            return "Pure Voice could not read microphone audio for live text."
        case .audioEngineFailed(let message):
            return "Live text could not start: \(message)"
        }
    }
}

public final class LiveSpeechPreviewService: @unchecked Sendable {
    public typealias UpdateHandler = @Sendable (_ text: String, _ isFinal: Bool) -> Void
    public typealias ErrorHandler = @Sendable (_ message: String) -> Void

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    public func requestPermission() async -> Bool {
        await requestAuthorization() == .authorized
    }

    deinit {
        stop()
    }

    public func start(onUpdate: @escaping UpdateHandler, onError: @escaping ErrorHandler) async throws {
        stop()

        let authorizationStatus = await requestAuthorization()
        try Task.checkCancellation()
        guard authorizationStatus == .authorized else {
            throw LiveSpeechPreviewError.authorizationDenied
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw LiveSpeechPreviewError.recognizerUnavailable
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw LiveSpeechPreviewError.onDeviceRecognitionUnavailable
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        try Task.checkCancellation()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw LiveSpeechPreviewError.inputUnavailable
        }

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    onUpdate(text, result.isFinal)
                }
            }

            if let error {
                onError(error.localizedDescription)
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try Task.checkCancellation()
            try engine.start()
            try Task.checkCancellation()
        } catch {
            engine.stop()
            inputNode.removeTap(onBus: 0)
            request.endAudio()
            task.cancel()
            if error is CancellationError {
                throw error
            }
            throw LiveSpeechPreviewError.audioEngineFailed(error.localizedDescription)
        }

        audioEngine = engine
        recognitionRequest = request
        recognitionTask = task
        tapInstalled = true
    }

    public func stop() {
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        if audioEngine?.isRunning == true {
            audioEngine?.stop()
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
