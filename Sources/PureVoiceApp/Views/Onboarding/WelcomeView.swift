import PureVoiceCore
import SwiftUI

enum InstallEstimates {
    static let whisperSize = "~140 MB"
    static let whisperTime = "~30 seconds"
    static let parakeetSize = "~600 MB"
    static let parakeetTime = "2-4 minutes"
}

struct WelcomeView: View {
    @EnvironmentObject private var state: AppState
    let onComplete: () -> Void
    @State private var screen: WelcomeFlowScreen = .welcome
    @State private var selectedEngine: STTEngine = .whisper
    @State private var readyEngine: STTEngine = .whisper

    var body: some View {
        ZStack {
            switch screen {
            case .welcome:
                WelcomeScreen {
                    screen = .permissions
                }

            case .permissions:
                PermissionsScreen {
                    screen = .engineChoice
                }

            case .engineChoice:
                EngineChoiceScreen(selectedEngine: $selectedEngine) {
                    screen = .install
                }

            case .install:
                STTInstallView(engine: selectedEngine) { result in
                    switch result {
                    case .success:
                        readyEngine = selectedEngine
                        screen = .done
                    case .failure:
                        state.selectInstalledSTTEngineFromInstallFlow(.whisper)
                        if state.sttEngineIsAvailable(.whisper) {
                            readyEngine = .whisper
                            screen = .done
                        } else {
                            selectedEngine = .whisper
                            screen = .engineChoice
                        }
                    }
                }

            case .done:
                DoneScreen(engine: readyEngine) {
                    onComplete()
                }
            }
        }
        .padding(32)
    }
}

private enum WelcomeFlowScreen {
    case welcome
    case permissions
    case engineChoice
    case install
    case done
}
