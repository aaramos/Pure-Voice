import PureVoiceCore
import SwiftUI

struct PermissionsScreen: View {
    @EnvironmentObject private var state: AppState
    @State private var microphoneStatus: OnboardingPermissionStatus = .pending
    @State private var speechRecognitionStatus: OnboardingPermissionStatus = .pending
    @State private var accessibilityStatus: OnboardingPermissionStatus = .pending
    @State private var appleStatus: OnboardingPermissionStatus = .pending
    @State private var didStartChecks = false

    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Pure Voice needs access")
                .font(.largeTitle.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 18) {
                PermissionRow(
                    title: "Microphone",
                    detail: "Required to record your voice.",
                    status: microphoneStatus,
                    actionTitle: "Open System Settings",
                    action: state.openMicrophonePrivacySettings
                )

                PermissionRow(
                    title: "Accessibility",
                    detail: "Lets Pure Voice paste into the active window. Optional - you can still copy/paste manually.",
                    status: accessibilityStatus,
                    actionTitle: "Open System Settings",
                    action: state.openAccessibilityPrivacySettings
                )

                PermissionRow(
                    title: "Speech Recognition",
                    detail: "Shows a live on-device transcript while you record. Optional - final transcription still works without it.",
                    status: speechRecognitionStatus,
                    actionTitle: "Open System Settings",
                    action: state.openSpeechRecognitionPrivacySettings
                )

                PermissionRow(
                    title: "Apple Intelligence",
                    detail: "Used to polish your transcripts on-device.",
                    status: appleStatus,
                    actionTitle: "Open System Settings",
                    action: state.openAppleIntelligenceSettings
                )
            }

            Spacer()

            if microphoneStatus.isBlocked {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pure Voice can't work without microphone access.")
                        .font(.callout.weight(.semibold))
                    Text("Open System Settings, grant microphone access, then try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Open System Settings") {
                            state.openMicrophonePrivacySettings()
                        }
                        Button("Try Again") {
                            Task { await runChecks() }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(14)
                .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack {
                    Spacer()
                    Button("Continue", action: onContinue)
                        .keyboardShortcut(.defaultAction)
                        .disabled(microphoneStatus.isChecking)
                }
            }
        }
        .task {
            guard !didStartChecks else { return }
            didStartChecks = true
            await runChecks()
        }
    }

    private func runChecks() async {
        microphoneStatus = .checking("Requesting...")
        let microphoneGranted = await state.requestMicrophonePermissionForOnboarding()
        microphoneStatus = microphoneGranted
            ? .granted("Granted")
            : .needsAttention("Microphone denied. Pure Voice needs microphone access to record.")

        guard microphoneGranted else {
            speechRecognitionStatus = .pending
            accessibilityStatus = .pending
            appleStatus = .pending
            return
        }

        speechRecognitionStatus = .checking("Requesting...")
        let speechRecognitionGranted = await state.requestSpeechRecognitionPermissionForOnboarding()
        speechRecognitionStatus = speechRecognitionGranted
            ? .granted("Granted")
            : .needsAttention("Speech Recognition denied. Live text will be unavailable, but final transcription will still work.")

        accessibilityStatus = .checking("Checking...")
        let accessibilityGranted = state.requestAccessibilityPermissionForOnboarding(prompt: true)
        accessibilityStatus = accessibilityGranted
            ? .granted("Granted")
            : .needsAttention("Accessibility denied. You can still use Pure Voice; paste with Command-V manually.")

        appleStatus = .checking("Checking...")
        let availability = await state.refreshAppleFoundationAvailability()
        appleStatus = availability == .available
            ? .granted("Available")
            : .needsAttention(state.llmStatus)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let status: OnboardingPermissionStatus
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.tint)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(status.shortLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .needsAttention(let message) = status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(actionTitle, action: action)
                        .font(.caption)
                }
            }
        }
    }
}

private enum OnboardingPermissionStatus: Equatable {
    case pending
    case checking(String)
    case granted(String)
    case needsAttention(String)

    var symbolName: String {
        switch self {
        case .pending:
            "circle"
        case .checking:
            "circle.fill"
        case .granted:
            "checkmark.circle.fill"
        case .needsAttention:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending:
            .secondary
        case .checking:
            .accentColor
        case .granted:
            .green
        case .needsAttention:
            .orange
        }
    }

    var shortLabel: String {
        switch self {
        case .pending:
            "Pending"
        case .checking(let label):
            label
        case .granted(let label):
            label
        case .needsAttention:
            "Needs attention"
        }
    }

    var isBlocked: Bool {
        if case .needsAttention = self {
            true
        } else {
            false
        }
    }

    var isChecking: Bool {
        if case .checking = self {
            true
        } else {
            false
        }
    }
}
