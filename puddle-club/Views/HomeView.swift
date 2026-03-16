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
    @Query private var patternStores: [PatternStore]

    private var patternStore: PatternStore? { patternStores.first }

    @Binding var searchText: String

    @State private var pipelineState = PipelineState()
    @State private var pipeline: ProcessingPipeline?
    @AppStorage("aiProvider") private var aiProviderRaw: String = AIProvider.openai.rawValue
    @AppStorage("dismissedWeeklyInsight") private var dismissedInsight: String = ""


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

    private func hasNew(for type: ContentType) -> Bool {
        screenshotsForType(type).contains { $0.isNew }
    }

    private var puddleGroups: [HomePuddleGroup] {
        availableTypes.map { type in
            let groupScreenshots = screenshotsForType(type)
            return HomePuddleGroup(
                type: type,
                screenshots: groupScreenshots,
                hasDot: hasNew(for: type)
            )
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let viewportMid = CGPoint(
                    x: geo.frame(in: .global).midX,
                    y: geo.frame(in: .global).midY
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let insight = patternStore?.weeklyInsight,
                           !insight.isEmpty,
                           insight != dismissedInsight {
                            WeeklyRecapCard(insight: insight) {
                                dismissedInsight = insight
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 18)
                        }

                        if puddleGroups.isEmpty {
                            EmptyPuddleState(searchText: searchText)
                                .padding(.horizontal, 24)
                                .padding(.top, 56)
                        } else {
                            HoneycombPuddleFeed(
                                groups: puddleGroups,
                                viewportMid: viewportMid
                            )
                            .padding(.horizontal, 18)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                    }
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


// MARK: - Home Puddle Models

private struct HomePuddleGroup: Identifiable {
    enum PreviewTier: Equatable {
        case small
        case medium
        case large

        var canvasSize: CGSize {
            switch self {
            case .small:
                CGSize(width: 192, height: 206)
            case .medium:
                CGSize(width: 226, height: 224)
            case .large:
                CGSize(width: 258, height: 238)
            }
        }

        var footprintHeight: CGFloat {
            switch self {
            case .small:
                224
            case .medium:
                244
            case .large:
                260
            }
        }

        var baseBubbleDiameter: CGFloat {
            switch self {
            case .small:
                72
            case .medium:
                82
            case .large:
                92
            }
        }

        var maxPreviewCount: Int {
            switch self {
            case .small:
                3
            case .medium, .large:
                5
            }
        }
    }

    let type: ContentType
    let screenshots: [Screenshot]
    let hasDot: Bool

    var id: ContentType { type }

    var tier: PreviewTier {
        switch screenshots.count {
        case ...3:
            .small
        case 4...5:
            .medium
        default:
            .large
        }
    }

    var previewCount: Int {
        min(screenshots.count, tier.maxPreviewCount)
    }

    var previewScreenshots: [Screenshot] {
        Array(screenshots.prefix(previewCount))
    }
}

private enum PuddleLayoutStyle: CaseIterable {
    case bloom
    case drift
    case orbit
    case cove
}

private struct PuddlePreviewPlacement {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let zIndex: Double
}

private struct PuddleLabelPlacement {
    let alignment: Alignment
    let xOffset: CGFloat
    let yOffset: CGFloat
}


// MARK: - Weekly Recap Card

private struct WeeklyRecapCard: View {
    let insight: String
    let onDismiss: () -> Void

    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 16

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Text("YOUR WEEKLY RECAP")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(insight)
                    .font(.system(size: fontSize))
                    // .lineSpacing(fontSize * 0.1)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 16)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.bottom, 20)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.173, green: 0.173, blue: 0.173),
                             Color(red: 0.122, green: 0.122, blue: 0.122)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.horizontal, 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 6)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(16)
            }
        }
    }
}


// MARK: - Puddle Group Card

private struct HoneycombPuddleFeed: View {
    let groups: [HomePuddleGroup]
    let viewportMid: CGPoint

    private struct FeedStyle {
        let alignment: HorizontalAlignment
        let xOffset: CGFloat
        let yOffset: CGFloat
    }

    private let styles: [FeedStyle] = [
        FeedStyle(alignment: .leading, xOffset: 8, yOffset: 0),
        FeedStyle(alignment: .trailing, xOffset: -20, yOffset: -34),
        FeedStyle(alignment: .leading, xOffset: -10, yOffset: -10),
        FeedStyle(alignment: .trailing, xOffset: -4, yOffset: -42)
    ]

    private func style(for index: Int) -> FeedStyle {
        styles[index % styles.count]
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                let destination: AnyView = group.screenshots.count == 1
                    ? AnyView(ScreenshotDetailView(screenshot: group.screenshots[0]))
                    : AnyView(GroupDetailView(type: group.type, screenshots: group.screenshots))
                let style = style(for: index)

                HoneycombPuddleCell(
                    group: group,
                    viewportMid: viewportMid,
                    xOffset: style.xOffset,
                    destination: destination
                )
                .frame(maxWidth: .infinity, alignment: style.alignment == .leading ? .leading : .trailing)
                .offset(y: style.yOffset)
            }
        }
    }
}

private struct HoneycombPuddleCell: View {
    let group: HomePuddleGroup
    let viewportMid: CGPoint
    let xOffset: CGFloat
    let destination: AnyView

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let focusPoint = CGPoint(x: viewportMid.x, y: viewportMid.y - 210)
            let distanceX = frame.midX - focusPoint.x
            let distanceY = frame.midY - focusPoint.y
            let distance = sqrt((distanceX * distanceX) + (distanceY * distanceY))
            let normalized = min(distance / 560, 1)
            let blurProgress = max((normalized - 0.28) / 0.72, 0)
            let scale = 1.06 - (normalized * 0.14)
            let opacity = 1 - (normalized * 0.18)
            let blur = blurProgress * 1.6
            let yLift = normalized * 10

            NavigationLink(destination: destination) {
                PuddleGroupCard(group: group)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .blur(radius: blur)
                    .offset(x: xOffset, y: yLift)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: group.tier.canvasSize.width, height: group.tier.footprintHeight)
    }
}


private struct PuddleGroupCard: View {
    let group: HomePuddleGroup

    var body: some View {
        PuddlePreviewView(group: group)
            .frame(width: group.tier.canvasSize.width, height: group.tier.footprintHeight)
            .contentShape(Rectangle())
    }
}


// MARK: - Puddle Preview View

private struct PuddlePreviewView: View {
    let group: HomePuddleGroup
    private let minimumBubbleGap: CGFloat = 10

    private var style: PuddleLayoutStyle {
        let index = stableHash(group.type.rawValue) % PuddleLayoutStyle.allCases.count
        return PuddleLayoutStyle.allCases[index]
    }

    private func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for scalar in string.unicodeScalars {
            hash = hash &* 31 &+ UInt64(scalar.value)
        }
        return Int(hash % UInt64(Int.max))
    }

    private func placements(for count: Int) -> [PuddlePreviewPlacement] {
        switch (style, count) {
        case (_, 1):
            return [
                PuddlePreviewPlacement(x: 0.50, y: 0.48, size: 1.34, zIndex: 1)
            ]
        case (.bloom, 2):
            return [
                PuddlePreviewPlacement(x: 0.36, y: 0.56, size: 1.02, zIndex: 1),
                PuddlePreviewPlacement(x: 0.67, y: 0.34, size: 0.84, zIndex: 2)
            ]
        case (.bloom, 3):
            return [
                PuddlePreviewPlacement(x: 0.34, y: 0.41, size: 1.08, zIndex: 3),
                PuddlePreviewPlacement(x: 0.68, y: 0.31, size: 0.78, zIndex: 1),
                PuddlePreviewPlacement(x: 0.60, y: 0.74, size: 0.74, zIndex: 2)
            ]
        case (.bloom, 4):
            return [
                PuddlePreviewPlacement(x: 0.31, y: 0.45, size: 1.04, zIndex: 4),
                PuddlePreviewPlacement(x: 0.62, y: 0.24, size: 0.74, zIndex: 2),
                PuddlePreviewPlacement(x: 0.70, y: 0.60, size: 0.72, zIndex: 1),
                PuddlePreviewPlacement(x: 0.49, y: 0.80, size: 0.62, zIndex: 3)
            ]
        case (.bloom, 5):
            return [
                PuddlePreviewPlacement(x: 0.31, y: 0.46, size: group.tier == .large ? 1.12 : 1.02, zIndex: 5),
                PuddlePreviewPlacement(x: 0.61, y: 0.23, size: 0.78, zIndex: 2),
                PuddlePreviewPlacement(x: 0.77, y: 0.54, size: 0.72, zIndex: 1),
                PuddlePreviewPlacement(x: 0.54, y: 0.78, size: 0.66, zIndex: 3),
                PuddlePreviewPlacement(x: 0.18, y: 0.72, size: 0.56, zIndex: 4)
            ]
        case (.drift, 2):
            return [
                PuddlePreviewPlacement(x: 0.43, y: 0.36, size: 0.90, zIndex: 2),
                PuddlePreviewPlacement(x: 0.64, y: 0.65, size: 1.05, zIndex: 1)
            ]
        case (.drift, 3):
            return [
                PuddlePreviewPlacement(x: 0.34, y: 0.28, size: 0.76, zIndex: 1),
                PuddlePreviewPlacement(x: 0.63, y: 0.44, size: 1.04, zIndex: 3),
                PuddlePreviewPlacement(x: 0.43, y: 0.76, size: 0.72, zIndex: 2)
            ]
        case (.drift, 4):
            return [
                PuddlePreviewPlacement(x: 0.29, y: 0.30, size: 0.72, zIndex: 1),
                PuddlePreviewPlacement(x: 0.58, y: 0.30, size: 0.78, zIndex: 2),
                PuddlePreviewPlacement(x: 0.69, y: 0.63, size: 1.00, zIndex: 4),
                PuddlePreviewPlacement(x: 0.34, y: 0.74, size: 0.66, zIndex: 3)
            ]
        case (.drift, 5):
            return [
                PuddlePreviewPlacement(x: 0.28, y: 0.28, size: 0.70, zIndex: 1),
                PuddlePreviewPlacement(x: 0.54, y: 0.24, size: 0.78, zIndex: 2),
                PuddlePreviewPlacement(x: 0.76, y: 0.46, size: 0.70, zIndex: 3),
                PuddlePreviewPlacement(x: 0.58, y: 0.72, size: group.tier == .large ? 1.02 : 0.92, zIndex: 5),
                PuddlePreviewPlacement(x: 0.24, y: 0.69, size: 0.68, zIndex: 4)
            ]
        case (.orbit, 2):
            return [
                PuddlePreviewPlacement(x: 0.34, y: 0.44, size: 1.00, zIndex: 2),
                PuddlePreviewPlacement(x: 0.69, y: 0.52, size: 0.84, zIndex: 1)
            ]
        case (.orbit, 3):
            return [
                PuddlePreviewPlacement(x: 0.50, y: 0.28, size: 0.74, zIndex: 1),
                PuddlePreviewPlacement(x: 0.30, y: 0.63, size: 0.86, zIndex: 2),
                PuddlePreviewPlacement(x: 0.68, y: 0.59, size: 1.02, zIndex: 3)
            ]
        case (.orbit, 4):
            return [
                PuddlePreviewPlacement(x: 0.50, y: 0.24, size: 0.68, zIndex: 2),
                PuddlePreviewPlacement(x: 0.74, y: 0.47, size: 0.72, zIndex: 3),
                PuddlePreviewPlacement(x: 0.54, y: 0.74, size: 1.00, zIndex: 4),
                PuddlePreviewPlacement(x: 0.26, y: 0.55, size: 0.76, zIndex: 1)
            ]
        case (.orbit, 5):
            return [
                PuddlePreviewPlacement(x: 0.50, y: 0.20, size: 0.62, zIndex: 2),
                PuddlePreviewPlacement(x: 0.77, y: 0.40, size: 0.72, zIndex: 3),
                PuddlePreviewPlacement(x: 0.66, y: 0.74, size: 0.70, zIndex: 4),
                PuddlePreviewPlacement(x: 0.28, y: 0.68, size: 0.72, zIndex: 1),
                PuddlePreviewPlacement(x: 0.39, y: 0.42, size: group.tier == .large ? 1.08 : 0.96, zIndex: 5)
            ]
        case (.cove, 2):
            return [
                PuddlePreviewPlacement(x: 0.40, y: 0.64, size: 1.04, zIndex: 1),
                PuddlePreviewPlacement(x: 0.67, y: 0.34, size: 0.82, zIndex: 2)
            ]
        case (.cove, 3):
            return [
                PuddlePreviewPlacement(x: 0.28, y: 0.52, size: 0.70, zIndex: 1),
                PuddlePreviewPlacement(x: 0.56, y: 0.61, size: 1.04, zIndex: 3),
                PuddlePreviewPlacement(x: 0.69, y: 0.28, size: 0.72, zIndex: 2)
            ]
        case (.cove, 4):
            return [
                PuddlePreviewPlacement(x: 0.25, y: 0.58, size: 0.70, zIndex: 1),
                PuddlePreviewPlacement(x: 0.50, y: 0.70, size: 0.94, zIndex: 4),
                PuddlePreviewPlacement(x: 0.69, y: 0.48, size: 0.80, zIndex: 3),
                PuddlePreviewPlacement(x: 0.56, y: 0.22, size: 0.66, zIndex: 2)
            ]
        case (.cove, 5):
            return [
                PuddlePreviewPlacement(x: 0.19, y: 0.62, size: 0.60, zIndex: 1),
                PuddlePreviewPlacement(x: 0.40, y: 0.72, size: 0.70, zIndex: 2),
                PuddlePreviewPlacement(x: 0.66, y: 0.66, size: group.tier == .large ? 1.02 : 0.92, zIndex: 5),
                PuddlePreviewPlacement(x: 0.77, y: 0.38, size: 0.72, zIndex: 4),
                PuddlePreviewPlacement(x: 0.49, y: 0.22, size: 0.64, zIndex: 3)
            ]
        default:
            return [PuddlePreviewPlacement(x: 0.50, y: 0.48, size: 1.0, zIndex: 1)]
        }
    }

    private func separatedPlacements(
        from placements: [PuddlePreviewPlacement],
        in canvasSize: CGSize,
        baseDiameter: CGFloat
    ) -> [PuddlePreviewPlacement] {
        guard placements.count > 1 else { return placements }

        struct BubbleLayout {
            var center: CGPoint
            let radius: CGFloat
            let placement: PuddlePreviewPlacement
        }

        let edgeInset: CGFloat = 8
        let minXBounds = placements.map { baseDiameter * $0.size / 2 + edgeInset }
        let maxXBounds = placements.map { canvasSize.width - (baseDiameter * $0.size / 2) - edgeInset }
        let minYBounds = placements.map { baseDiameter * $0.size / 2 + edgeInset }
        let maxYBounds = placements.map { canvasSize.height - (baseDiameter * $0.size / 2) - edgeInset }

        var bubbles = placements.enumerated().map { index, placement in
            let radius = baseDiameter * placement.size / 2
            let rawCenter = CGPoint(
                x: canvasSize.width * placement.x,
                y: canvasSize.height * placement.y
            )
            return BubbleLayout(
                center: CGPoint(
                    x: min(max(rawCenter.x, minXBounds[index]), maxXBounds[index]),
                    y: min(max(rawCenter.y, minYBounds[index]), maxYBounds[index])
                ),
                radius: radius,
                placement: placement
            )
        }

        for _ in 0..<24 {
            for leftIndex in bubbles.indices {
                for rightIndex in bubbles.indices where rightIndex > leftIndex {
                    let dx = bubbles[rightIndex].center.x - bubbles[leftIndex].center.x
                    let dy = bubbles[rightIndex].center.y - bubbles[leftIndex].center.y
                    let distance = sqrt((dx * dx) + (dy * dy))
                    let requiredDistance = bubbles[leftIndex].radius + bubbles[rightIndex].radius + minimumBubbleGap

                    guard distance < requiredDistance else { continue }

                    let angle = distance > 0.001 ? CGPoint(x: dx / distance, y: dy / distance) : CGPoint(x: 1, y: 0)
                    let overlap = (requiredDistance - distance) / 2

                    bubbles[leftIndex].center.x -= angle.x * overlap
                    bubbles[leftIndex].center.y -= angle.y * overlap
                    bubbles[rightIndex].center.x += angle.x * overlap
                    bubbles[rightIndex].center.y += angle.y * overlap
                }
            }

            for index in bubbles.indices {
                bubbles[index].center.x = min(max(bubbles[index].center.x, minXBounds[index]), maxXBounds[index])
                bubbles[index].center.y = min(max(bubbles[index].center.y, minYBounds[index]), maxYBounds[index])
            }
        }

        return bubbles.map { bubble in
            PuddlePreviewPlacement(
                x: bubble.center.x / canvasSize.width,
                y: bubble.center.y / canvasSize.height,
                size: bubble.placement.size,
                zIndex: bubble.placement.zIndex
            )
        }
    }

    private var labelPlacement: PuddleLabelPlacement {
        switch style {
        case .bloom:
            return PuddleLabelPlacement(alignment: .topLeading, xOffset: 14, yOffset: 20)
        case .drift:
            return PuddleLabelPlacement(alignment: .bottomLeading, xOffset: 12, yOffset: -12)
        case .orbit:
            return PuddleLabelPlacement(alignment: .trailing, xOffset: 8, yOffset: 8)
        case .cove:
            return PuddleLabelPlacement(alignment: .bottomTrailing, xOffset: -10, yOffset: -18)
        }
    }

    var body: some View {
        let cards = group.previewScreenshots
        let canvasSize = group.tier.canvasSize
        let diameter = group.tier.baseBubbleDiameter
        let placements = separatedPlacements(
            from: placements(for: cards.count),
            in: canvasSize,
            baseDiameter: diameter
        )

        ZStack {
            ZStack {
                ForEach(Array(cards.indices), id: \.self) { index in
                    let screenshot = cards[index]
                    let placement = placements[index]
                    let bubbleSize = diameter * placement.size

                    PuddlePreviewTileView(screenshot: screenshot, diameter: bubbleSize)
                        .position(
                            x: canvasSize.width * placement.x,
                            y: canvasSize.height * placement.y
                        )
                        .zIndex(placement.zIndex)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)

            PuddleLabelView(
                title: group.type.displayName,
                count: group.screenshots.count,
                showsDot: group.hasDot
            )
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: labelPlacement.alignment)
            .offset(x: labelPlacement.xOffset, y: labelPlacement.yOffset)
        }
    }
}

private struct PuddleLabelView: View {
    let title: String
    let count: Int
    let showsDot: Bool

    var body: some View {
        HStack(spacing: 7) {
            if showsDot {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
            }

            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(count.formatted())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
    }
}


// MARK: - Puddle Preview Tile View

private struct PuddlePreviewTileView: View {
    let screenshot: Screenshot
    let diameter: CGFloat
    @State private var image: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.08)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(.secondary.opacity(0.16))
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(borderColor, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.34), radius: 18, x: 0, y: 10)
        .onAppear(perform: loadImage)
    }

    private func loadImage() {
        let targetDimension = max(diameter * 3, 220)
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [screenshot.localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            if let data = screenshot.imageData, let uiImage = UIImage(data: data) {
                image = uiImage
            }
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: targetDimension, height: targetDimension),
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            if let img {
                DispatchQueue.main.async { self.image = img }
            } else if let data = screenshot.imageData, let uiImage = UIImage(data: data) {
                DispatchQueue.main.async { self.image = uiImage }
            }
        }
    }
}


// MARK: - Empty State

private struct EmptyPuddleState: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 10) {
            Text(searchText.isEmpty ? "No puddles yet." : "No puddles match your search.")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)

            Text(searchText.isEmpty ? "Process screenshots to start forming groups." : "Try a different keyword or clear the search bar.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
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
