import AVFoundation
import Foundation

public enum AudioRecorderError: Error, LocalizedError, Equatable {
    case microphoneDenied
    case recorderUnavailable

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone permission is required to record."
        case .recorderUnavailable:
            return "The audio recorder is not available."
        }
    }
}

public final class AudioRecorderService: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    public override init() {
        super.init()
    }

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public func startRecording() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PureVoiceRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("recording-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioRecorderError.recorderUnavailable
        }

        self.recorder = recorder
        currentURL = url
        return url
    }

    public func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        return currentURL
    }

    public func currentLevel() -> Float {
        guard let recorder else { return -80 }
        recorder.updateMeters()
        let average = recorder.averagePower(forChannel: 0)
        let peak = recorder.peakPower(forChannel: 0)
        return max(average, peak - 6)
    }
}
