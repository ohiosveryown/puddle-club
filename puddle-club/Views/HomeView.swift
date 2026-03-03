import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Screenshot.addedToLibraryDate, order: .reverse) private var screenshots: [Screenshot]

    @State private var pipelineState = PipelineState()
    // Hold a strong reference so the actor isn't released mid-run
    @State private var pipeline: ProcessingPipeline?

    var body: some View {
        NavigationStack {
            List {
                ForEach(screenshots) { screenshot in
                    NavigationLink(destination: ScreenshotDetailView(screenshot: screenshot)) {
                        ScreenshotRow(screenshot: screenshot)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(screenshots[i]) }
                    try? modelContext.save()
                }
            }
            .navigationTitle("Puddle Club")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Process") { startPipeline() }
                        .disabled(pipelineState.isProcessing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
            .overlay {
                if pipelineState.isProcessing || pipelineState.currentPhase == "Complete" {
                    PipelineStatusView(state: pipelineState) {
                        pipelineState.currentPhase = ""
                    }
                }
            }
        }
    }

    private func startPipeline() {
        let container = modelContext.container
        let p = ProcessingPipeline(container: container, state: pipelineState)
        pipeline = p
        Task { await p.run() }
    }
}

// MARK: - Row

private struct ScreenshotRow: View {
    let screenshot: Screenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                statusBadge
                Text(screenshot.displayTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(screenshot.localIdentifier.prefix(8) + "…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let reflection = screenshot.reflection {
                Text(reflection)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        Text(screenshot.processingStatus)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch ProcessingStatus(rawValue: screenshot.processingStatus) {
        case .complete: return .green
        case .failed: return .red
        case .ocrInProgress, .openAIInProgress: return .orange
        case .ocrComplete: return .blue
        default: return .secondary
        }
    }
}
