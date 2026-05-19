import PureVoiceCore
import SwiftUI

struct STTInstallView: View {
    @EnvironmentObject private var state: AppState
    let engine: STTEngine
    let onComplete: (Result<Void, Error>) -> Void

    @State private var phase: STTInstallPhase = .installing
    @State private var rawErrorMessage = ""
    @State private var didStartInstall = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            switch phase {
            case .installing:
                installingContent
            case .success:
                successContent
            case .failure:
                failureContent
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !didStartInstall else { return }
            didStartInstall = true
            await runInstall()
        }
    }

    private var installingContent: some View {
        VStack(spacing: 18) {
            Text("Installing \(engine.displayName)")
                .font(.largeTitle.weight(.semibold))

            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 360)

            Text(progressText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
    }

    private var successContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("\(engine.displayName) is ready")
                .font(.largeTitle.weight(.semibold))

            Button("Continue") {
                onComplete(.success(()))
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var failureContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 46))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Couldn't install \(engine.displayName)")
                .font(.title.weight(.semibold))

            Text(state.displaySTTInstallError(from: rawErrorMessage))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430)

            DisclosureGroup("Technical details") {
                Text(rawErrorMessage.isEmpty ? "No technical details were returned." : rawErrorMessage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 430, alignment: .leading)
            }
            .frame(maxWidth: 430)

            HStack {
                Button("Try Again") {
                    Task { await runInstall() }
                }
                .keyboardShortcut(.defaultAction)

                Button("Use Whisper Instead") {
                    state.selectInstalledSTTEngineFromInstallFlow(.whisper)
                    onComplete(.failure(STTInstallFlowError.failed(rawErrorMessage)))
                }
            }
        }
    }

    private var progressText: String {
        if let status = state.sttInstallStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
           !status.isEmpty {
            return status
        }

        switch engine {
        case .whisper:
            return "Installing Whisper. This usually takes \(InstallEstimates.whisperTime)."
        case .parakeet:
            return "Installing Parakeet. This usually takes \(InstallEstimates.parakeetTime)."
        }
    }

    private func runInstall() async {
        phase = .installing
        rawErrorMessage = ""

        await state.loadIfNeeded()
        await state.refreshSTTHealth()
        if state.sttEngineIsAvailable(engine) {
            state.selectInstalledSTTEngineFromInstallFlow(engine)
            phase = .success
            return
        }

        await state.installSTTDependencies(engine: engine)
        await state.refreshSTTHealth()

        let health = state.sttHealth(for: engine)
        if health.available {
            state.selectInstalledSTTEngineFromInstallFlow(engine)
            phase = .success
        } else {
            rawErrorMessage = health.message
            phase = .failure
        }
    }
}

private enum STTInstallPhase {
    case installing
    case success
    case failure
}

private enum STTInstallFlowError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}
