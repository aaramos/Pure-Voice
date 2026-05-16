import SwiftUI

struct HUDView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: state.stageIconName)
                    .font(.system(size: 28))
                    .foregroundStyle(state.stage == .recording ? .red : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.stage.label)
                        .font(.title3.weight(.semibold))
                    Text("\(state.selectedPersona.name) -> \(state.activeModelLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            if state.stage == .recording {
                ProgressView()
                    .progressViewStyle(.linear)
            } else if state.stage == .transcribing || state.stage == .polishing {
                ProgressView()
            }

            if let error = state.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else if !state.polishedPreview.isEmpty {
                Text(state.polishedPreview)
                    .font(.callout)
                    .lineLimit(4)
            } else {
                Text("Control Option Space starts and stops recording.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(minWidth: 340, minHeight: 180)
        .background(.regularMaterial)
    }
}
