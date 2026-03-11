import SwiftUI
import SwiftData
import Photos

// MARK: - Action model

enum ScreenshotAction {
    case openURL(URL)
    case openInMaps(query: String)
    case searchMusic(query: String)
    case searchWeb(query: String)

    var label: String {
        switch self {
        case .openURL(let url):
            return url.host ?? "Open Link"
        case .openInMaps(let query):
            return "Open \"\(query)\" in Maps"
        case .searchMusic(let query):
            return "Search \"\(query)\" in Music"
        case .searchWeb(let query):
            return "Search \"\(query)\""
        }
    }

    var icon: String {
        switch self {
        case .openURL: return "safari"
        case .openInMaps: return "map"
        case .searchMusic: return "music.note"
        case .searchWeb: return "magnifyingglass"
        }
    }

    var url: URL? {
        switch self {
        case .openURL(let url):
            return url
        case .openInMaps(let query):
            var c = URLComponents(string: "maps://")!
            c.queryItems = [URLQueryItem(name: "q", value: query)]
            return c.url
        case .searchMusic(let query):
            var c = URLComponents(string: "https://music.apple.com/search")!
            c.queryItems = [URLQueryItem(name: "term", value: query)]
            return c.url
        case .searchWeb(let query):
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: query)]
            return c.url
        }
    }
}

// MARK: - Scroll offset preference

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ViewportSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Detail view

struct ScreenshotDetailView: View {
    let screenshot: Screenshot
    var siblings: [Screenshot]? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Screenshot.addedToLibraryDate, order: .reverse) private var allScreenshots: [Screenshot]
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var scrollProgress: CGFloat = 0

    @State private var currentLocalIdentifier: String

    init(screenshot: Screenshot, siblings: [Screenshot]? = nil) {
        self.screenshot = screenshot
        self.siblings = siblings
        _currentLocalIdentifier = State(initialValue: screenshot.localIdentifier)
    }

    private var screenshots: [Screenshot] {
        siblings ?? allScreenshots
    }

    private var currentScreenshot: Screenshot {
        screenshots.first(where: { $0.localIdentifier == currentLocalIdentifier }) ?? screenshot
    }

    private var currentIndex: Int? {
        screenshots.firstIndex(where: { $0.localIdentifier == currentLocalIdentifier })
    }

    private func createdDateString(for shot: Screenshot) -> String {
        let date = shot.creationDate ?? shot.addedToLibraryDate
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    @ViewBuilder
    private var dateLabel: some View {
        let dateText = createdDateString(for: currentScreenshot)
        ZStack {
            Text(dateText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text(dateText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .opacity(scrollProgress)
        }
    }

    var body: some View {
        TabView(selection: $currentLocalIdentifier) {
            ForEach(screenshots) { shot in
                ScreenshotPageView(screenshot: shot, scrollProgress: $scrollProgress)
                    .tag(shot.localIdentifier)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            HeaderBlurOverlay(progress: scrollProgress)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 3) {
                    Text(currentScreenshot.displayTitle)
                        .font(.headline)
                    dateLabel
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("Delete this screenshot?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(currentScreenshot)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

}

// MARK: - Header blur overlay

private struct HeaderBlurOverlay: View {
    /// 0 = no overlay, 1 = fully active
    let progress: CGFloat

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.12 + 0.99 * progress),
                        Color.black.opacity(0.04 + 0.08 * progress),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .mask(
                LinearGradient(
                    colors: [
                        .white,
                        .white,
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 170)
            .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Per-screenshot page content

private struct ScreenshotPageView: View {
    let screenshot: Screenshot
    @Binding var scrollProgress: CGFloat

    @State private var image: UIImage? = nil
    @State private var viewportSize: CGSize = .zero
    @ScaledMetric(relativeTo: .footnote) private var aestheticNotesFontSize: CGFloat = 13

    // Image layout (uses viewport from GeometryReader to avoid UIScreen.main)
    private var imageMaxHeight: CGFloat {
        let h = viewportSize.height > 0 ? viewportSize.height : 600
        return h * 0.7
    }

    /// Primary color from the image (first dominant color) for the drop shadow; falls back to black.
    private var imageShadowColor: Color {
        Color.fromDominantColorString(screenshot.dominantColors.first) ?? .black
    }

    private let scrollTransitionDistance: CGFloat = 80

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Image
                imageSection

                // MARK: Overall aesthetic (values only)
                if let notes = screenshot.aestheticNotes, !notes.isEmpty {
                    let topNotes = Array(notes.prefix(2))
                    Text(topNotes.joined(separator: " · "))
                        .font(.system(size: aestheticNotesFontSize, weight: .regular, design: .serif))
                        .tracking(-0.25)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                // MARK: Content type pill
                if let ct = ContentType(rawValue: screenshot.contentType ?? ""),
                   ct != .unknown {
                    Label(ct.displayName, systemImage: ct.sfSymbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.secondary.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.horizontal, 20)
                }

                VStack(alignment: .leading, spacing: 0) {

                    // MARK: Primary action
                    if let action = primaryAction, let url = action.url {
                        Link(destination: url) {
                            Label(action.label, systemImage: action.icon)
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(.tint)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }

                    // MARK: Reflection
                    if let desc = screenshot.reflection {
                        section {
                            Text(desc)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        } header: {
                            sectionLabel("Reflection", icon: "sparkles")
                        }
                    }

                    // MARK: Tags
                    if !screenshot.tags.isEmpty {
                        section {
                            TagCloud(items: screenshot.tags.map { $0.value })
                        } header: {
                            sectionLabel("Tags", icon: "tag")
                        }
                    }

                }
                .padding(.bottom, 32)
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: ScrollOffsetKey.self,
                            value: geo.frame(in: .named("scroll")).minY
                        )
                }
            )
        }
        .contentMargins(.bottom, 80, for: .scrollContent)
        .coordinateSpace(name: "scroll")
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ViewportSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(ViewportSizeKey.self) { viewportSize = $0 }
        .onPreferenceChange(ScrollOffsetKey.self) { minY in
            // minY is content top in scroll space: 0 at top, negative when scrolled down
            let progress = minY <= 0 ? min(1, -minY / scrollTransitionDistance) : 0
            scrollProgress = progress
        }
        .onAppear(perform: loadImage)
    }

    @ViewBuilder
    private var imageSection: some View {
        Group {
            if let image {
                // Match CSS: max-height: 70vh; width: auto; object-fit: contain
                let availableWidth = viewportSize.width > 0 ? viewportSize.width : 400
                let maxWidth = availableWidth - 24 // 12pt padding each side
                let maxHeight = imageMaxHeight
                let originalSize = image.size
                let widthScale = maxWidth / originalSize.width
                let heightScale = maxHeight / originalSize.height
                let scale = min(widthScale, heightScale)
                let targetWidth = originalSize.width * scale
                let targetHeight = originalSize.height * scale

                Image(uiImage: image)
                    .resizable()
                    .frame(width: targetWidth, height: targetHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.1))
                    .frame(height: min(CGFloat(320), imageMaxHeight))
                    .overlay { ProgressView() }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .shadow(color: imageShadowColor.opacity(0.24), radius: 80, x: 0, y: 15)
        .shadow(color: imageShadowColor.opacity(0.09), radius: 18, x: 0, y: 4)
        .shadow(color: imageShadowColor.opacity(0.06), radius: 5, x: 0, y: 1)
        .padding(.horizontal, 12)
        .padding(.top, 64)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func section<Header: View, Content: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header()
            content()
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Action resolution

    private var primaryAction: ScreenshotAction? {
        let openAIEntities = screenshot.entities.filter { $0.source == "openai" }
        let mapsTypes: Set<EntityType> = [.restaurant, .venue, .hotel, .location]
        let musicTypes: Set<EntityType> = [.artist, .band, .album]

        // 1. Travel always opens in Maps
        if ContentType(rawValue: screenshot.contentType ?? "") == .travel {
            let mapsQuery = openAIEntities
                .filter({ mapsTypes.contains(EntityType(rawValue: $0.entityType) ?? .other) })
                .max(by: { $0.confidence < $1.confidence })?.name
                ?? screenshot.title
                ?? "Travel"
            return .openInMaps(query: mapsQuery)
        }

        // 2. AI-extracted source URL — social post/profile takes priority
        if let raw = screenshot.sourceURL,
           let url = URL(string: raw) {
            return .openURL(url)
        }

        // 2. URL detected in OCR text
        if let ocrText = screenshot.ocrText,
           let url = firstURL(in: ocrText) {
            let enhanced = enhancedSocialURL(url, ocrText: ocrText) ?? url
            return .openURL(enhanced)
        }

        // 3. Maps entity
        if let entity = openAIEntities
            .filter({ mapsTypes.contains(EntityType(rawValue: $0.entityType) ?? .other) })
            .max(by: { $0.confidence < $1.confidence }) {
            return .openInMaps(query: entity.name)
        }

        // 4. Music entity
        if let entity = openAIEntities
            .filter({ musicTypes.contains(EntityType(rawValue: $0.entityType) ?? .other) })
            .max(by: { $0.confidence < $1.confidence }) {
            return .searchMusic(query: entity.name)
        }

        // 3. Content-type fallback using highest-confidence entity as the query
        let topEntity = openAIEntities.max(by: { $0.confidence < $1.confidence })

        switch ContentType(rawValue: screenshot.contentType ?? "") {
        case .food, .travel, .architecture:
            let query = topEntity?.name ?? screenshot.contentType ?? ""
            return query.isEmpty ? nil : .openInMaps(query: query)
        case .nature:
            guard let query = topEntity?.name, !query.isEmpty else { return nil }
            return .openInMaps(query: query)
        case .music:
            let query = topEntity?.name ?? ""
            return query.isEmpty ? nil : .searchMusic(query: query)
        case .product, .art, .design:
            let query = topEntity?.name ?? ""
            return query.isEmpty ? nil : .searchWeb(query: query)
        default:
            return nil
        }
    }

    private func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)
            .flatMap { $0.url }
    }

    /// When OCR only captures the root domain (e.g. "instagram.com" from a
    /// truncated address bar), try to build the full profile URL.
    private func enhancedSocialURL(_ url: URL, ocrText: String) -> URL? {
        let socialHosts: Set<String> = [
            "instagram.com", "twitter.com", "x.com",
            "tiktok.com", "threads.net", "facebook.com"
        ]
        guard let host = url.host,
              socialHosts.contains(host),
              url.path.isEmpty || url.path == "/" else {
            return nil // already has a path — no enhancement needed
        }

        // Prefer explicit @handle in OCR (common on Twitter/X)
        if let handle = atHandle(in: ocrText) {
            return URL(string: "https://\(host)/\(handle)")
        }

        // Fall back to the highest-confidence entity that looks like a username
        // (no spaces, ≤ 40 chars — rules out display names like "Kidwell Fabrications LLC")
        let username = screenshot.entities
            .filter { $0.source == "openai" }
            .sorted { $0.confidence > $1.confidence }
            .compactMap { e -> String? in
                let n = e.normalizedName
                return (!n.contains(" ") && n.count <= 40) ? n : nil
            }
            .first

        guard let username else { return nil }
        return URL(string: "https://\(host)/\(username)")
    }

    private func atHandle(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"@(\w{1,40})"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Image loading
    private func loadImage() {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [screenshot.localIdentifier], options: nil)
        guard let asset = result.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        // Use a generous fixed size; PHImageManager will scale down as needed
        let size = CGSize(width: 1170, height: 2532)

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            guard let result else { return }
            DispatchQueue.main.async { self.image = result }
        }
    }
}

// MARK: - Tag cloud

private struct TagCloud: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Flow layout (iOS 16+)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(subviews: subviews, in: proposal.width ?? 0).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = place(subviews: subviews, in: bounds.width)
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct Result { var frames: [CGRect]; var size: CGSize }

    private func place(subviews: Subviews, in maxWidth: CGFloat) -> Result {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return Result(frames: frames, size: CGSize(width: maxWidth, height: y + rowHeight))
    }
}
