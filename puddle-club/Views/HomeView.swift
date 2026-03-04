import SwiftUI
import SwiftData
import Photos

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Screenshot.addedToLibraryDate, order: .reverse) private var screenshots: [Screenshot]

    @Binding var searchText: String

    @State private var pipelineState = PipelineState()
    @State private var pipeline: ProcessingPipeline?
    @AppStorage("aiProvider") private var aiProviderRaw: String = AIProvider.openai.rawValue

    var filteredScreenshots: [Screenshot] {
        guard !searchText.isEmpty else { return screenshots }
        let q = searchText.lowercased()
        return screenshots.filter {
            ($0.displayTitle.lowercased().contains(q)) ||
            ($0.reflection?.lowercased().contains(q) ?? false) ||
            ($0.tags.contains(where: { tag in tag.value.lowercased().contains(q) }))
        }
    }

    // Stable deterministic height — same screenshot always gets the same height
    private func cellHeight(for screenshot: Screenshot, colWidth: CGFloat) -> CGFloat {
        var hash: UInt64 = 5381
        for c in screenshot.localIdentifier.unicodeScalars {
            hash = hash &* 31 &+ UInt64(c.value)
        }
        let t = CGFloat(hash % 1000) / 1000.0   // 0.0 – 1.0
        return colWidth * (1.0 + t * 1.4)        // colWidth × 1.0 – 2.4
    }

    private func columns(colWidth: CGFloat, spacing: CGFloat) -> (left: [Screenshot], right: [Screenshot]) {
        var left: [Screenshot] = []
        var right: [Screenshot] = []
        var leftH: CGFloat = 0
        var rightH: CGFloat = 0

        for screenshot in filteredScreenshots {
            let h = cellHeight(for: screenshot, colWidth: colWidth)
            if leftH <= rightH {
                left.append(screenshot)
                leftH += (leftH > 0 ? spacing : 0) + h
            } else {
                right.append(screenshot)
                rightH += (rightH > 0 ? spacing : 0) + h
            }
        }
        return (left, right)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let spacing: CGFloat = 12
                let colWidth = (geo.size.width - spacing * 3) / 2
                let cols = columns(colWidth: colWidth, spacing: spacing)

                ScrollView {
                    HStack(alignment: .top, spacing: spacing) {
                        LazyVStack(spacing: spacing) {
                            ForEach(cols.left) { screenshot in
                                NavigationLink(destination: ScreenshotDetailView(screenshot: screenshot)) {
                                    MasonryImageCell(screenshot: screenshot, width: colWidth, clipHeight: cellHeight(for: screenshot, colWidth: colWidth))
                                }
                                .buttonStyle(.plain)
                                .contextMenu { deleteButton(for: screenshot) }
                            }
                        }
                        .frame(width: colWidth)
                        LazyVStack(spacing: spacing) {
                            ForEach(cols.right) { screenshot in
                                NavigationLink(destination: ScreenshotDetailView(screenshot: screenshot)) {
                                    MasonryImageCell(screenshot: screenshot, width: colWidth, clipHeight: cellHeight(for: screenshot, colWidth: colWidth))
                                }
                                .buttonStyle(.plain)
                                .contextMenu { deleteButton(for: screenshot) }
                            }
                        }
                        .frame(width: colWidth)
                    }
                    .padding(spacing)
                }
                .contentMargins(.bottom, 80, for: .scrollContent)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("PuddleClubLogo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                }
            }
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

    @ViewBuilder
    private func deleteButton(for screenshot: Screenshot) -> some View {
        Button(role: .destructive) {
            modelContext.delete(screenshot)
            try? modelContext.save()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func startPipeline() {
        let container = modelContext.container
        let provider = AIProvider(rawValue: aiProviderRaw) ?? .openai
        let p = ProcessingPipeline(container: container, state: pipelineState, provider: provider)
        pipeline = p
        Task { await p.run() }
    }
}

// MARK: - Masonry Cell

private struct MasonryImageCell: View {
    let screenshot: Screenshot
    let width: CGFloat
    var clipHeight: CGFloat? = nil
    @State private var image: UIImage?

    private var height: CGFloat {
        clipHeight ?? (width / 0.46)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.1))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear(perform: loadImage)
    }

    private func loadImage() {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [screenshot.localIdentifier], options: nil)
        guard let asset = result.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 500, height: 1000),
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            guard let img else { return }
            DispatchQueue.main.async { self.image = img }
        }
    }
}

// MARK: - Floating Search Bar

struct FloatingSearchBar: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var labelColor: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(labelColor)
                .frame(width: 8, height: 8)

            TextField(text: $text, prompt: Text("Search or ask a question...").foregroundStyle(labelColor.opacity(0.45))) { }
                .focused($focused)
                .foregroundStyle(labelColor)

            Spacer()

            Button {
                // placeholder — voice input in future
            } label: {
                Image("WaveformIcon")
                    .renderingMode(.template)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black, in: Circle())
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .glassEffect(in: Capsule())
        .onChange(of: focused) { _, new in isFocused = new }
        .onChange(of: isFocused) { _, new in focused = new }
    }
}
