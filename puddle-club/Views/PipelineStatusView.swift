import SwiftUI

struct PipelineStatusView: View {
    let state: PipelineState
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if state.isProcessing {
                    ProgressView(value: state.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                }

                Text(state.currentPhase)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if state.totalCount > 0 {
                    Text("\(state.processedCount) / \(state.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let error = state.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if !state.isProcessing, let dismiss = onDismiss {
                    Button("Dismiss") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)
        }
    }
}
