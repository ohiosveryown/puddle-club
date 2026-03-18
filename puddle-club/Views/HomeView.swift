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

    private let debugLayoutMode = true

    private var debugGroups: [[HomePuddleGroup]] {
        guard let seed = screenshots.first else { return [] }
        let tierCounts = [1, 5, 15, 25, 35]
        let allTypes = ContentType.allCases.filter { $0 != .unknown }
        return tierCounts.enumerated().map { tierIndex, count in
            (0..<3).map { styleIndex in
                let type = allTypes[(tierIndex * 3 + styleIndex) % allTypes.count]
                return HomePuddleGroup(
                    type: type,
                    screenshots: Array(repeating: seed, count: count),
                    hasDot: false
                )
            }
        }
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

                    if debugLayoutMode {
                        let tierLabels = ["XXSmall (1)", "ExtraSmall (2-9)", "Small (10-19)", "Medium (20-29)", "Large (30+)"]
                        ScrollView {
                            VStack(alignment: .leading, spacing: 40) {
                                ForEach(debugGroups.indices, id: \.self) { tierIndex in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(tierLabels[tierIndex])
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 20)
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(alignment: .top, spacing: 0) {
                                                ForEach(debugGroups[tierIndex].indices, id: \.self) { styleIndex in
                                                    PuddlePreviewView(group: debugGroups[tierIndex][styleIndex])
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 24)
                            .padding(.bottom, 48)
                        }
                    } else if puddleGroups.isEmpty {
                        EmptyPuddleState(searchText: searchText)
                            .padding(.horizontal, 24)
                            .padding(.top, 56)

                        Spacer(minLength: 0)
                    } else {
                        OpenCanvasPuddleScroller(
                            groups: puddleGroups,
                            viewportSize: geo.size
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case xxSmall
        case extraSmall
        case small
        case medium
        case large

        var canvasSize: CGSize {
            switch self {
            case .xxSmall:
                CGSize(width: 160, height: 172)
            case .extraSmall:
                CGSize(width: 192, height: 206)
            case .small:
                CGSize(width: 210, height: 218)
            case .medium:
                CGSize(width: 240, height: 230)
            case .large:
                CGSize(width: 270, height: 248)
            }
        }

        var footprintHeight: CGFloat {
            switch self {
            case .xxSmall:
                196
            case .extraSmall:
                224
            case .small:
                236
            case .medium:
                250
            case .large:
                266
            }
        }

        var baseBubbleDiameter: CGFloat {
            switch self {
            case .xxSmall:
                88
            case .extraSmall:
                78
            case .small:
                74
            case .medium:
                80
            case .large:
                88
            }
        }

        var maxPreviewCount: Int {
            switch self {
            case .xxSmall:
                1
            case .extraSmall:
                2
            case .small:
                3
            case .medium:
                4
            case .large:
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
        case 1:
            .xxSmall
        case 2...9:
            .extraSmall
        case 10...19:
            .small
        case 20...29:
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

private struct OpenCanvasPuddleScroller: View {
    let groups: [HomePuddleGroup]
    let viewportSize: CGSize
    @State private var hasCenteredInitialView = false
    private let columnCount = 3
    private let columnSpacing: CGFloat = 212
    private let rowSpacing: CGFloat = 182
    private let horizontalCanvasOverscan: CGFloat = 96
    private let verticalCanvasOverscan: CGFloat = 0
    private let horizontalContentInset: CGFloat = 52
    private let verticalContentInset: CGFloat = 0

    private var rowCount: Int {
        max(Int(ceil(Double(groups.count) / Double(columnCount))), 2)
    }

    private var maxGroupHalfWidth: CGFloat {
        groups.map { $0.tier.canvasSize.width / 2 }.max() ?? 129
    }

    private var maxGroupHalfHeight: CGFloat {
        groups.map { $0.tier.footprintHeight / 2 }.max() ?? 130
    }

    private func basePosition(for index: Int) -> CGPoint {
        let row = index / columnCount
        let column = index % columnCount

        let startX = horizontalContentInset + maxGroupHalfWidth
        let baseX = startX + (CGFloat(column) * columnSpacing)
        let x = row.isMultiple(of: 2) ? baseX : baseX + (columnSpacing / 2)
        let startY = verticalContentInset + maxGroupHalfHeight
        let y = startY + (CGFloat(row) * rowSpacing)

        return CGPoint(x: x, y: y)
    }

    private var contentBounds: CGRect {
        guard !groups.isEmpty else {
            return CGRect(
                x: 0,
                y: 0,
                width: viewportSize.width,
                height: viewportSize.height
            )
        }

        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for (index, group) in groups.enumerated() {
            let point = basePosition(for: index)
            let halfWidth = group.tier.canvasSize.width / 2
            let halfHeight = group.tier.footprintHeight / 2

            minX = min(minX, point.x - halfWidth)
            maxX = max(maxX, point.x + halfWidth)
            minY = min(minY, point.y - halfHeight)
            maxY = max(maxY, point.y + halfHeight)
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private var canvasSize: CGSize {
        CGSize(
            width: max(viewportSize.width + horizontalCanvasOverscan, contentBounds.width + (horizontalContentInset * 2)),
            height: max(viewportSize.height + verticalCanvasOverscan, contentBounds.height + (verticalContentInset * 2))
        )
    }

    private var contentOffset: CGPoint {
        CGPoint(
            x: ((canvasSize.width - contentBounds.width) / 2) - contentBounds.minX,
            y: max((canvasSize.height - contentBounds.height) * 0.5, verticalContentInset) - contentBounds.minY
        )
    }

    private func position(for index: Int) -> CGPoint {
        let point = basePosition(for: index)

        return CGPoint(
            x: point.x + contentOffset.x,
            y: point.y + contentOffset.y
        )
    }

    private var contentCenter: CGPoint {
        CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    }

    var body: some View {
        GeometryReader { viewportProxy in
            let viewportCenter = CGPoint(
                x: viewportProxy.size.width / 2,
                y: viewportProxy.size.height / 2
            )

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .position(contentCenter)
                            .id("canvas-center")

                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            let destination: AnyView = group.screenshots.count == 1
                                ? AnyView(ScreenshotDetailView(screenshot: group.screenshots[0]))
                                : AnyView(GroupDetailView(type: group.type, screenshots: group.screenshots))

                            HoneycombPuddleCell(
                                group: group,
                                viewportCenter: viewportCenter,
                                destination: destination
                            )
                            .position(position(for: index))
                        }
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 6)
                }
                .coordinateSpace(name: "openCanvasViewport")
                .onAppear {
                    guard !hasCenteredInitialView else { return }
                    hasCenteredInitialView = true
                    DispatchQueue.main.async {
                        proxy.scrollTo("canvas-center", anchor: .center)
                    }
                }
            }
        }
    }
}

private struct HoneycombPuddleCell: View {
    let group: HomePuddleGroup
    let viewportCenter: CGPoint
    let destination: AnyView
    private let focusYOffset: CGFloat = 92

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("openCanvasViewport"))
            let focusPoint = CGPoint(x: viewportCenter.x, y: viewportCenter.y - focusYOffset)
            let distanceX = frame.midX - focusPoint.x
            let distanceY = frame.midY - focusPoint.y
            let distance = sqrt((distanceX * distanceX) + (distanceY * distanceY))
            let normalized = min(distance / 300, 1)
            let focus = 1 - normalized
            let scale = 0.7 + (focus * 0.3)
            let opacity = 0.1 + (focus * 0.9)
            let blur = normalized * 2.5
            let saturation = 0.75 + (focus * 0.25)

            NavigationLink(destination: destination) {
                PuddleGroupCard(group: group)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .blur(radius: blur)
                    .saturation(saturation)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.18), value: scale)
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

    private func placements() -> [PuddlePreviewPlacement] {
        switch (style, group.tier) {

        // MARK: XXSmall — 1 bubble
        // Single large circle; label position varies by style
        case (.bloom, .xxSmall):
            return [PuddlePreviewPlacement(x: 0.46, y: 0.46, size: 1.22, zIndex: 1)]
        case (.drift, .xxSmall):
            return [PuddlePreviewPlacement(x: 0.54, y: 0.48, size: 1.12, zIndex: 1)]
        case (.orbit, .xxSmall):
            return [PuddlePreviewPlacement(x: 0.46, y: 0.54, size: 1, zIndex: 1)]

        // MARK: ExtraSmall — 2 bubbles
        // bloom: large upper-left + small lower-right (dramatic contrast)
        case (.bloom, .extraSmall):
            return [
                PuddlePreviewPlacement(x: 0.36, y: 0.40, size: 1.16, zIndex: 2),
                PuddlePreviewPlacement(x: 0.76, y: 0.74, size: 0.52, zIndex: 1)
            ]
        // drift: label top-left; large center-right + medium lower-left
        case (.drift, .extraSmall):
            return [
                PuddlePreviewPlacement(x: 0.64, y: 0.48, size: 1.06, zIndex: 1),
                PuddlePreviewPlacement(x: 0.28, y: 0.68, size: 0.72, zIndex: 2)
            ]
        // orbit: two circles side-by-side, moderate contrast
        case (.orbit, .extraSmall):
            return [
                PuddlePreviewPlacement(x: 0.36, y: 0.58, size: 1.02, zIndex: 1),
                PuddlePreviewPlacement(x: 0.68, y: 0.38, size: 0.80, zIndex: 2)
            ]

        // MARK: Small — 3 bubbles
        // bloom: two large circles side-by-side at top + one small below
        case (.bloom, .small):
            return [
                PuddlePreviewPlacement(x: 0.28, y: 0.36, size: 1.04, zIndex: 2),
                PuddlePreviewPlacement(x: 0.62, y: 0.30, size: 0.94, zIndex: 3),
                PuddlePreviewPlacement(x: 0.64, y: 0.74, size: 0.52, zIndex: 1)
            ]
        // drift: large left + smaller right + small lower-right
        case (.drift, .small):
            return [
                PuddlePreviewPlacement(x: 0.28, y: 0.46, size: 1.10, zIndex: 3),
                PuddlePreviewPlacement(x: 0.68, y: 0.34, size: 0.70, zIndex: 2),
                PuddlePreviewPlacement(x: 0.74, y: 0.74, size: 0.52, zIndex: 1)
            ]
        // orbit: large lower-center + medium upper-right + small upper-left
        case (.orbit, .small):
            return [
                PuddlePreviewPlacement(x: 0.44, y: 0.66, size: 1.10, zIndex: 3),
                PuddlePreviewPlacement(x: 0.72, y: 0.34, size: 0.74, zIndex: 2),
                PuddlePreviewPlacement(x: 0.22, y: 0.32, size: 0.56, zIndex: 1)
            ]

        // MARK: Medium — 4 bubbles
        // bloom: one dominant + medium upper-right + two small lower
        case (.bloom, .medium):
            return [
                PuddlePreviewPlacement(x: 0.34, y: 0.36, size: 1.24, zIndex: 4),
                PuddlePreviewPlacement(x: 0.72, y: 0.26, size: 0.64, zIndex: 2),
                PuddlePreviewPlacement(x: 0.74, y: 0.64, size: 0.52, zIndex: 1),
                PuddlePreviewPlacement(x: 0.46, y: 0.80, size: 0.46, zIndex: 3)
            ]
        // drift: large center-right + medium lower-left + two small
        case (.drift, .medium):
            return [
                PuddlePreviewPlacement(x: 0.62, y: 0.42, size: 1.16, zIndex: 4),
                PuddlePreviewPlacement(x: 0.80, y: 0.22, size: 0.52, zIndex: 1),
                PuddlePreviewPlacement(x: 0.30, y: 0.56, size: 0.82, zIndex: 3),
                PuddlePreviewPlacement(x: 0.56, y: 0.80, size: 0.50, zIndex: 2)
            ]
        // orbit: large lower-right + medium upper-left + two small scattered
        case (.orbit, .medium):
            return [
                PuddlePreviewPlacement(x: 0.60, y: 0.64, size: 1.18, zIndex: 4),
                PuddlePreviewPlacement(x: 0.72, y: 0.30, size: 0.70, zIndex: 2),
                PuddlePreviewPlacement(x: 0.22, y: 0.32, size: 0.56, zIndex: 1),
                PuddlePreviewPlacement(x: 0.78, y: 0.62, size: 0.44, zIndex: 3)
            ]

        // MARK: Large — 5 bubbles
        // bloom: large left + 4 varied right-and-below
        case (.bloom, .large):
            return [
                PuddlePreviewPlacement(x: 0.28, y: 0.42, size: 1.16, zIndex: 5),
                PuddlePreviewPlacement(x: 0.64, y: 0.22, size: 0.78, zIndex: 2),
                PuddlePreviewPlacement(x: 0.80, y: 0.54, size: 0.66, zIndex: 1),
                PuddlePreviewPlacement(x: 0.60, y: 0.76, size: 0.58, zIndex: 3),
                PuddlePreviewPlacement(x: 0.18, y: 0.74, size: 0.52, zIndex: 4)
            ]
        // drift: scattered diagonal, dominant lower-center
        case (.drift, .large):
            return [
                PuddlePreviewPlacement(x: 0.22, y: 0.26, size: 0.64, zIndex: 1),
                PuddlePreviewPlacement(x: 0.52, y: 0.20, size: 0.74, zIndex: 2),
                PuddlePreviewPlacement(x: 0.78, y: 0.40, size: 0.66, zIndex: 3),
                PuddlePreviewPlacement(x: 0.60, y: 0.72, size: 1.08, zIndex: 5),
                PuddlePreviewPlacement(x: 0.20, y: 0.68, size: 0.60, zIndex: 4)
            ]
        // orbit: dominant center + 4 orbiting at varying sizes
        case (.orbit, .large):
            return [
                PuddlePreviewPlacement(x: 0.42, y: 0.44, size: 1.12, zIndex: 5),
                PuddlePreviewPlacement(x: 0.76, y: 0.26, size: 0.66, zIndex: 2),
                PuddlePreviewPlacement(x: 0.80, y: 0.66, size: 0.58, zIndex: 3),
                PuddlePreviewPlacement(x: 0.46, y: 0.80, size: 0.54, zIndex: 4),
                PuddlePreviewPlacement(x: 0.16, y: 0.60, size: 0.62, zIndex: 1)
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
        switch (style, group.tier) {

        // MARK: XXSmall
        case (.bloom, .xxSmall):
            return PuddleLabelPlacement(alignment: .bottomTrailing, xOffset: 0, yOffset: -50)
        case (.drift, .xxSmall):
            return PuddleLabelPlacement(alignment: .bottomLeading, xOffset: 60, yOffset: -20)
        case (.orbit, .xxSmall):
            return PuddleLabelPlacement(alignment: .topLeading, xOffset: 0, yOffset: 32)

        // MARK: ExtraSmall
        case (.bloom, .extraSmall):
            return PuddleLabelPlacement(alignment: .bottomTrailing, xOffset: -10, yOffset: -18)
        case (.drift, .extraSmall):
            return PuddleLabelPlacement(alignment: .topLeading, xOffset: 12, yOffset: 16)
        case (.orbit, .extraSmall):
            return PuddleLabelPlacement(alignment: .bottomTrailing, xOffset: -10, yOffset: -18)

        // MARK: Small
        case (.bloom, .small):
            return PuddleLabelPlacement(alignment: .bottomTrailing, xOffset: -10, yOffset: -18)
        case (.drift, .small):
            return PuddleLabelPlacement(alignment: .bottomLeading, xOffset: 12, yOffset: -12)
        case (.orbit, .small):
            return PuddleLabelPlacement(alignment: .bottomTrailing, xOffset: -10, yOffset: -18)

        // MARK: Medium
        case (.bloom, .medium):
            return PuddleLabelPlacement(alignment: .topLeading, xOffset: 12, yOffset: 16)
        case (.drift, .medium):
            return PuddleLabelPlacement(alignment: .bottomLeading, xOffset: 12, yOffset: -12)
        case (.orbit, .medium):
            return PuddleLabelPlacement(alignment: .bottomLeading, xOffset: 12, yOffset: -12)

        // MARK: Large
        case (.bloom, .large):
            return PuddleLabelPlacement(alignment: .topLeading, xOffset: 12, yOffset: 16)
        case (.drift, .large):
            return PuddleLabelPlacement(alignment: .bottomTrailing, xOffset: -10, yOffset: -18)
        case (.orbit, .large):
            return PuddleLabelPlacement(alignment: .bottomTrailing, xOffset: -10, yOffset: -18)

        default:
            return PuddleLabelPlacement(alignment: .bottomTrailing, xOffset: -10, yOffset: -18)
        }
    }

    var body: some View {
        let cards = group.previewScreenshots
        let canvasSize = group.tier.canvasSize
        let diameter = group.tier.baseBubbleDiameter
        let placements = separatedPlacements(
            from: placements(),
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
    @Environment(\.colorScheme) private var colorScheme

    private var labelColor: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        HStack(spacing: 7) {
            if showsDot {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
            }

            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(labelColor)
                .lineLimit(1)

            Text(count.formatted())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(labelColor.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
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
