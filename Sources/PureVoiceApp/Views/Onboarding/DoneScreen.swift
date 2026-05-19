import PureVoiceCore
import SwiftUI

struct DoneScreen: View {
    let engine: STTEngine
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("\(engine.displayName) is ready")
                    .font(.largeTitle.weight(.semibold))

                Text("You're all set. Pure Voice will open now.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Start Using Pure Voice", action: onStart)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
    }
}
