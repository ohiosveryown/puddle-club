import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Screenshot.addedToLibraryDate, order: .reverse) private var screenshots: [Screenshot]

    @Binding var searchText: String

    @State private var pipelineState = PipelineState()
    // Hold a strong reference so the actor isn't released mid-run
    @State private var pipeline: ProcessingPipeline?

    var filteredScreenshots: [Screenshot] {
        guard !searchText.isEmpty else { return screenshots }
        let q = searchText.lowercased()
        return screenshots.filter {
            ($0.displayTitle.lowercased().contains(q)) ||
            ($0.reflection?.lowercased().contains(q) ?? false) ||
            ($0.tags.contains(where: { tag in tag.value.lowercased().contains(q) }))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredScreenshots) { screenshot in
                    NavigationLink(destination: ScreenshotDetailView(screenshot: screenshot)) {
                        ScreenshotRow(screenshot: screenshot)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(filteredScreenshots[i]) }
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

// MARK: - Floating Search Bar

struct FloatingSearchBar: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)

            TextField(text: $text, prompt: Text("Search or ask a question...").foregroundStyle(.white.opacity(0.55))) { }
                .focused($focused)
                .foregroundStyle(.white)

            Spacer()

            Button {
                // placeholder — voice input in future
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: Capsule())
        .onChange(of: focused) { _, new in isFocused = new }
        .onChange(of: isFocused) { _, new in focused = new }
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
