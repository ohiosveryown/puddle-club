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

// MARK: - Detail view

struct ScreenshotDetailView: View {
    let screenshot: Screenshot

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage? = nil
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Image
                imageSection

                VStack(alignment: .leading, spacing: 20) {

                    // MARK: Primary action
                    if let action = primaryAction, let url = action.url {
                        Link(destination: url) {
                            Label(action.label, systemImage: action.icon)
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.tint)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // MARK: Aesthetic description
                    if let desc = screenshot.aestheticDescription {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("Aesthetic", icon: "sparkles")
                            Text(desc)
                                .font(.body)
                        }
                    }

                    // MARK: Content type
                    if let contentType = screenshot.contentType {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("Content", icon: "square.grid.2x2")
                            Text(contentType.capitalized)
                                .font(.subheadline)
                        }
                    }

                    // MARK: Entities
                    let openAIEntities = screenshot.entities.filter { $0.source == "openai" }
                    if !openAIEntities.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("Entities", icon: "person.text.rectangle")
                            TagCloud(items: openAIEntities.map { "\($0.name) · \($0.entityType)" })
                        }
                    }

                    // MARK: Tags
                    if !screenshot.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("Tags", icon: "tag")
                            TagCloud(items: screenshot.tags.map { $0.value })
                        }
                    }

                    // MARK: Mood
                    if !screenshot.moodTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("Mood", icon: "heart.text.square")
                            TagCloud(items: screenshot.moodTags)
                        }
                    }

                    // MARK: Colors
                    if !screenshot.dominantColors.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("Colors", icon: "paintpalette")
                            TagCloud(items: screenshot.dominantColors)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .top)
        .onAppear { loadImage() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("Delete this screenshot?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(screenshot)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var imageSection: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        } else {
            Rectangle()
                .fill(.secondary.opacity(0.1))
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .overlay { ProgressView() }
        }
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Action resolution

    private var primaryAction: ScreenshotAction? {
        // 1. URL detected in OCR text
        if let ocrText = screenshot.ocrText,
           let url = firstURL(in: ocrText) {
            let enhanced = enhancedSocialURL(url, ocrText: ocrText) ?? url
            return .openURL(enhanced)
        }

        let openAIEntities = screenshot.entities.filter { $0.source == "openai" }

        // 2. Search for actionable entity types directly — don't rely on a single
        //    top-confidence entity, since a high-confidence non-actionable entity
        //    (e.g. "flowers · flora") would otherwise block a lower-confidence
        //    actionable one (e.g. "Carlsbad Flower Fields · location").

        let mapsTypes: Set<EntityType> = [.restaurant, .venue, .hotel, .location]
        let musicTypes: Set<EntityType> = [.artist, .band, .album]

        if let entity = openAIEntities
            .filter({ mapsTypes.contains(EntityType(rawValue: $0.entityType) ?? .other) })
            .max(by: { $0.confidence < $1.confidence }) {
            return .openInMaps(query: entity.name)
        }

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
        // Wrap tags using a flowing layout via fixed-width measurement
        GeometryReader { geo in
            self.generateContent(in: geo)
        }
        .frame(height: height)
    }

    // Pre-compute rows to know the height (uses 358pt — standard iPhone content width)
    private var rows: [[String]] {
        var rows: [[String]] = [[]]
        var currentWidth: CGFloat = 0
        let maxWidth: CGFloat = 358
        let spacing: CGFloat = 8

        for item in items {
            let itemWidth = itemSize(item)
            if currentWidth + itemWidth + spacing > maxWidth && !rows.last!.isEmpty {
                rows.append([item])
                currentWidth = itemWidth
            } else {
                rows[rows.endIndex - 1].append(item)
                currentWidth += itemWidth + spacing
            }
        }
        return rows
    }

    private var height: CGFloat {
        CGFloat(rows.count) * 30 + CGFloat(max(rows.count - 1, 0)) * 8
    }

    private func itemSize(_ text: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 12)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return size.width + 20 // horizontal padding
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var x: CGFloat = 0
        var y: CGFloat = 0
        let spacing: CGFloat = 8
        let rowHeight: CGFloat = 28

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                let width = itemSize(item)
                pill(item)
                    .alignmentGuide(.leading) { _ in
                        let result = -x
                        if x + width + spacing > geo.size.width {
                            x = width + spacing
                            y += rowHeight + spacing
                        } else {
                            x += width + spacing
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in -y }
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}
