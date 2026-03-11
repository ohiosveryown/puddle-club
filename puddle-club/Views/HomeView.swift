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

// MARK: - Visible date preference key

private struct CellDateItem: Equatable {
    let date: Date
    let minY: CGFloat
    let maxY: CGFloat
}

private struct CellDatesKey: PreferenceKey {
    static let defaultValue: [CellDateItem] = []
    static func reduce(value: inout [CellDateItem], nextValue: () -> [CellDateItem]) {
        value.append(contentsOf: nextValue())
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

    @State private var selectedContentType: ContentType? = nil
    @State private var visibleDates: [Date] = []

    var availableTypes: [ContentType] {
        let seen = Set(
            screenshots
                .compactMap { ContentType(rawValue: $0.contentType ?? "") }
                .filter { $0 != .unknown }
        )
        return ContentType.allCases.filter { seen.contains($0) && $0 != .unknown }
    }

    var filteredScreenshots: [Screenshot] {
        var results = Array(screenshots)
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            results = results.filter {
                ($0.displayTitle.lowercased().contains(q)) ||
                ($0.reflection?.lowercased().contains(q) ?? false) ||
                ($0.tags.contains(where: { $0.value.lowercased().contains(q) }))
            }
        }
        if let type = selectedContentType {
            results = results.filter { ($0.contentType ?? "") == type.rawValue }
        }
        return results
    }

    var dateRangeLabel: String? {
        guard !visibleDates.isEmpty else { return nil }
        let sorted = visibleDates.sorted()
        return Self.formatDateRange(from: sorted.first!, to: sorted.last!)
    }

    private static func formatDateRange(from lo: Date, to hi: Date) -> String {
        let cal = Calendar.current
        let loC = cal.dateComponents([.year, .month, .day], from: lo)
        let hiC = cal.dateComponents([.year, .month, .day], from: hi)

        if loC.year == hiC.year && loC.month == hiC.month && loC.day == hiC.day {
            return lo.formatted(.dateTime.month(.abbreviated).day().year())
        }

        let loMon = lo.formatted(.dateTime.month(.abbreviated))
        let loDay = lo.formatted(.dateTime.day())
        let hiMon = hi.formatted(.dateTime.month(.abbreviated))
        let hiDay = hi.formatted(.dateTime.day())
        let hiYear = hi.formatted(.dateTime.year())

        if loC.year == hiC.year {
            if loC.month == hiC.month {
                return "\(loMon) \(loDay)–\(hiDay), \(hiYear)"
            } else {
                return "\(loMon) \(loDay)–\(hiMon) \(hiDay), \(hiYear)"
            }
        } else {
            let loYear = lo.formatted(.dateTime.year())
            return "\(loMon) \(loDay), \(loYear)–\(hiMon) \(hiDay), \(hiYear)"
        }
    }

    // Stable deterministic height — same screenshot always gets the same height
    private func cellHeight(for screenshot: Screenshot, colWidth: CGFloat) -> CGFloat {
        var hash: UInt64 = 5381
        for c in screenshot.localIdentifier.unicodeScalars {
            hash = hash &* 31 &+ UInt64(c.value)
        }
        let t = CGFloat(hash % 1000) / 1000.0
        return colWidth * (1.0 + t * 1.4)
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
            VStack(spacing: 0) {
                PuddleTabStrip(
                    selected: $selectedContentType,
                    available: availableTypes,
                    screenshots: Array(screenshots)
                )

                if let label = dateRangeLabel {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .transition(.opacity)
                }

                GeometryReader { geo in
                    let spacing: CGFloat = 12
                    let colWidth = (geo.size.width - spacing * 3) / 2
                    let cols = columns(colWidth: colWidth, spacing: spacing)
                    let viewportH = geo.size.height

                    ScrollView {
                        HStack(alignment: .top, spacing: spacing) {
                            masonryColumn(
                                screenshots: cols.left,
                                colWidth: colWidth,
                                spacing: spacing
                            )
                            masonryColumn(
                                screenshots: cols.right,
                                colWidth: colWidth,
                                spacing: spacing
                            )
                        }
                        .padding(spacing)
                    }
                    .coordinateSpace(.named("scroll"))
                    .contentMargins(.bottom, 80, for: .scrollContent)
                    .onPreferenceChange(CellDatesKey.self) { items in
                        visibleDates = items
                            .filter { $0.maxY > 0 && $0.minY < viewportH }
                            .map(\.date)
                    }
                }
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
    private func masonryColumn(screenshots: [Screenshot], colWidth: CGFloat, spacing: CGFloat) -> some View {
        LazyVStack(spacing: spacing) {
            ForEach(screenshots) { screenshot in
                let h = cellHeight(for: screenshot, colWidth: colWidth)
                NavigationLink(destination: ScreenshotDetailView(screenshot: screenshot)) {
                    MasonryImageCell(screenshot: screenshot, width: colWidth, clipHeight: h)
                }
                .buttonStyle(.plain)
                .contextMenu { deleteButton(for: screenshot) }
                .overlay(
                    GeometryReader { cellGeo in
                        let frame = cellGeo.frame(in: .named("scroll"))
                        let date = screenshot.creationDate ?? screenshot.addedToLibraryDate
                        Color.clear.preference(
                            key: CellDatesKey.self,
                            value: [CellDateItem(date: date, minY: frame.minY, maxY: frame.maxY)]
                        )
                    }
                )
            }
        }
        .frame(width: colWidth)
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

// MARK: - Puddle Tab Strip

private struct PuddleTabStrip: View {
    @Binding var selected: ContentType?
    let available: [ContentType]
    let screenshots: [Screenshot]

    private static let incompleteStatuses: Set<String> = [
        ProcessingStatus.pending.rawValue,
        ProcessingStatus.ocrInProgress.rawValue,
        ProcessingStatus.ocrComplete.rawValue,
        ProcessingStatus.openAIInProgress.rawValue
    ]

    private func hasUnprocessed(for type: ContentType?) -> Bool {
        if let type {
            return screenshots.contains {
                ($0.contentType ?? "") == type.rawValue &&
                Self.incompleteStatuses.contains($0.processingStatus)
            }
        } else {
            return screenshots.contains { Self.incompleteStatuses.contains($0.processingStatus) }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                PuddleTabPill(
                    icon: "photo.stack",
                    label: "All",
                    isSelected: selected == nil,
                    hasDot: hasUnprocessed(for: nil)
                ) { selected = nil }

                ForEach(available, id: \.self) { type in
                    PuddleTabPill(
                        icon: type.sfSymbol,
                        label: type.displayName,
                        isSelected: selected == type,
                        hasDot: hasUnprocessed(for: type)
                    ) { selected = type }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct PuddleTabPill: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let hasDot: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                if hasDot {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(backgroundColor)
            )
            .foregroundStyle(foregroundColor)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var backgroundColor: Color {
        switch colorScheme {
        case .dark:
            return .white.opacity(isSelected ? 0.22 : 0.10)
        default:
            return .black.opacity(isSelected ? 0.08 : 0.03)
        }
    }

    private var foregroundColor: Color {
        switch colorScheme {
        case .dark:
            return isSelected ? .white : .white.opacity(0.55)
        default:
            return isSelected ? .black : .black.opacity(0.55)
        }
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
