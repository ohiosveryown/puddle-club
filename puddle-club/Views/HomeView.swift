import SwiftUI
import SwiftData
import Photos

// MARK: - ContentType display helpers

extension ContentType {
    var displayName: String {
        switch self {
        case .food: return "Food"
        case .music: return "Music"
        case .travel: return "Travel"
        case .design: return "Design"
        case .fashion: return "Fashion"
        case .product: return "Product"
        case .architecture: return "Architecture"
        case .art: return "Art"
        case .text: return "Text"
        case .social: return "Social"
        case .event: return "Events"
        case .person: return "People"
        case .nature: return "Nature"
        case .woodworking: return "Woodworking"
        case .unknown: return "Other"
        }
    }

    var sfSymbol: String {
        switch self {
        case .food: return "fork.knife"
        case .music: return "music.note"
        case .travel: return "airplane"
        case .design: return "paintpalette"
        case .fashion: return "tshirt"
        case .product: return "bag"
        case .architecture: return "building.2"
        case .art: return "paintbrush"
        case .text: return "doc.text"
        case .social: return "person.2"
        case .event: return "calendar"
        case .person: return "person"
        case .nature: return "leaf"
        case .woodworking: return "hammer"
        case .unknown: return "questionmark"
        }
    }
}


// MARK: - HomeView

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Screenshot.addedToLibraryDate, order: .reverse) private var screenshots: [Screenshot]

    @Binding var searchText: String

    @State private var pipelineState = PipelineState()
    @State private var pipeline: ProcessingPipeline?
    @AppStorage("aiProvider") private var aiProviderRaw: String = AIProvider.openai.rawValue

    private static let incompleteStatuses: Set<String> = [
        ProcessingStatus.pending.rawValue,
        ProcessingStatus.ocrInProgress.rawValue,
        ProcessingStatus.ocrComplete.rawValue,
        ProcessingStatus.openAIInProgress.rawValue
    ]

    var availableTypes: [ContentType] {
        let seen = Set(
            filteredScreenshots
                .compactMap { ContentType(rawValue: $0.contentType ?? "") }
                .filter { $0 != .unknown }
        )
        return ContentType.allCases.filter { seen.contains($0) && $0 != .unknown }
    }

    var filteredScreenshots: [Screenshot] {
        guard !searchText.isEmpty else { return Array(screenshots) }
        let q = searchText.lowercased()
        return screenshots.filter {
            ($0.displayTitle.lowercased().contains(q)) ||
            ($0.reflection?.lowercased().contains(q) ?? false) ||
            ($0.tags.contains(where: { $0.value.lowercased().contains(q) }))
        }
    }

    private func screenshotsForType(_ type: ContentType) -> [Screenshot] {
        filteredScreenshots.filter { ($0.contentType ?? "") == type.rawValue }
    }

    private func hasUnprocessed(for type: ContentType) -> Bool {
        screenshotsForType(type).contains {
            Self.incompleteStatuses.contains($0.processingStatus)
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let hSpacing: CGFloat = 12
                let colWidth = (geo.size.width - hSpacing * 3) / 2

                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(colWidth), spacing: hSpacing),
                            GridItem(.fixed(colWidth), spacing: hSpacing)
                        ],
                        spacing: 44
                    ) {
                        ForEach(availableTypes, id: \.self) { type in
                            let typeScreenshots = screenshotsForType(type)
                            let destination: AnyView = typeScreenshots.count == 1
                                ? AnyView(ScreenshotDetailView(screenshot: typeScreenshots[0]))
                                : AnyView(GroupDetailView(type: type, screenshots: typeScreenshots))
                            NavigationLink(destination: destination) {
                                PuddleGroupCard(
                                    type: type,
                                    screenshots: typeScreenshots,
                                    colWidth: colWidth,
                                    hasDot: hasUnprocessed(for: type)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, hSpacing)
                    .padding(.top, 16)
                }
                .contentMargins(.bottom, 80, for: .scrollContent)
                .scrollDismissesKeyboard(.immediately)
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

    private func startPipeline() {
        let container = modelContext.container
        let provider = AIProvider(rawValue: aiProviderRaw) ?? .openai
        let p = ProcessingPipeline(container: container, state: pipelineState, provider: provider)
        pipeline = p
        Task { await p.run() }
    }
}


// MARK: - Puddle Group Card


private struct PuddleGroupCard: View {
    let type: ContentType
    let screenshots: [Screenshot]
    let colWidth: CGFloat
    let hasDot: Bool

    var body: some View {
        VStack(spacing: 16) {
            PuddleStackView(screenshots: screenshots, colWidth: colWidth)

            HStack(spacing: 8) {
                if hasDot {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                }

                Text(type.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(screenshots.count.formatted())
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: colWidth)
    }
}


// MARK: - Puddle Stack View

private struct PuddleStackView: View {
    let screenshots: [Screenshot]
    let colWidth: CGFloat

    private var cardWidth: CGFloat { colWidth * 0.55 }
    private var cardHeight: CGFloat { cardWidth * (212 / 124) }

    private var configs: [(transform: CGAffineTransform, scale: CGFloat, yOffset: CGFloat)] {
        let s = cardWidth / 124
        return [
            (CGAffineTransform(rotationAngle: -5 * .pi / 180).translatedBy(x: -52 * s, y: 20 * s), 0.88, -5),  // bottom
            (CGAffineTransform(rotationAngle:  9 * .pi / 180).translatedBy(x:  56 * s, y:  9 * s), 0.88, -5),  // middle
            (CGAffineTransform(rotationAngle:  3 * .pi / 180),                                       1.00,   0),  // top
        ]
    }

    var body: some View {
        let cards = Array(screenshots.prefix(3))
        let n = cards.count
        let ordered = Array(cards.reversed()) // back → front

        ZStack {
            ForEach(Array(ordered.enumerated()), id: \.offset) { localIdx, screenshot in
                let configIdx = (configs.count - n) + localIdx
                let cfg = configs[configIdx]
                StackCardView(screenshot: screenshot, width: cardWidth, height: cardHeight)
                    .scaleEffect(n == 1 ? 1 : cfg.scale)
                    .transformEffect(n == 1 ? .identity : cfg.transform)
                    .offset(y: n == 1 ? 0 : cfg.yOffset)
            }
        }
        .frame(width: colWidth, height: cardHeight + 40)
    }
}


// MARK: - Stack Card View

private struct StackCardView: View {
    let screenshot: Screenshot
    let width: CGFloat
    let height: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.15))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 16, x: 0, y: 8)
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
            targetSize: CGSize(width: 400, height: 600),
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
