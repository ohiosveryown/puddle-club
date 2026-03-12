import SwiftUI
import SwiftData
import Photos

// MARK: - Action model

enum ScreenshotAction {
    case openURL(URL)
    case openInMaps(query: String)
    case searchMusic(query: String, client: String?)
    case searchWeb(query: String)

    var title: String {
        switch self {
        case .openURL:
            return "Visit Website"
        case .openInMaps:
            return "Open in Maps"
        case .searchMusic(_, let client):
            return "Search in \(MusicClientInfo.displayName(for: client))"
        case .searchWeb:
            return "Search the Web"
        }
    }

    var subtitle: String {
        switch self {
        case .openURL(let url):
            return url.host() ?? url.absoluteString
        case .openInMaps(let query):
            return query
        case .searchMusic(let query, _):
            return query
        case .searchWeb(let query):
            return query
        }
    }

    var label: String {
        switch self {
        case .openURL(let url):
            return url.host ?? "Open Link"
        case .openInMaps(let query):
            return "Open \"\(query)\" in Maps"
        case .searchMusic(let query, let client):
            let appName = MusicClientInfo.displayName(for: client)
            return "Search \"\(query)\" in \(appName)"
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
        case .searchMusic(let query, let client):
            return MusicClientInfo.searchURL(for: client, query: query)
        case .searchWeb(let query):
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: query)]
            return c.url
        }
    }
}

private enum MusicClientInfo {
    private static let clientNames: Set<String> = [
        "spotify", "apple music", "youtube music", "tidal",
        "soundcloud", "amazon music", "podcasts"
    ]

    static func isClientName(_ name: String) -> Bool {
        clientNames.contains(name.lowercased())
    }

    static func displayName(for client: String?) -> String {
        switch client {
        case "spotify":       return "Spotify"
        case "apple_music":   return "Apple Music"
        case "youtube_music": return "YouTube Music"
        case "tidal":         return "Tidal"
        case "soundcloud":    return "SoundCloud"
        case "amazon_music":  return "Amazon Music"
        case "podcasts":      return "Podcasts"
        default:              return "Music"
        }
    }

    static func searchURL(for client: String?, query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch client {
        case "spotify":
            return URL(string: "spotify:search:\(encoded)")
        case "youtube_music":
            var c = URLComponents(string: "https://music.youtube.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: query)]
            return c.url
        case "tidal":
            return URL(string: "tidal://search/\(encoded)")
        case "soundcloud":
            var c = URLComponents(string: "https://soundcloud.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: query)]
            return c.url
        case "amazon_music":
            return URL(string: "amznmp3://search?q=\(encoded)")
        case "podcasts":
            var c = URLComponents(string: "podcasts://search")!
            c.queryItems = [URLQueryItem(name: "term", value: query)]
            return c.url
        default: // apple_music + unknown
            var c = URLComponents(string: "music://search")!
            c.queryItems = [URLQueryItem(name: "term", value: query)]
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

private enum DetailConfirmationModal {
    case hideScreenshot
    case deleteFromPhotos

    var title: String {
        switch self {
        case .hideScreenshot:
            return "Hide screenshot?"
        case .deleteFromPhotos:
            return "Delete from Photos?"
        }
    }

    var message: String {
        switch self {
        case .hideScreenshot:
            return "This will remove the screenshot from Puddle Club."
        case .deleteFromPhotos:
            return "This will remove the screenshot from your Photos library but keep it in Puddle Club."
        }
    }

    var confirmTitle: String {
        switch self {
        case .hideScreenshot:
            return "Hide screenshot"
        case .deleteFromPhotos:
            return "Delete from Photos"
        }
    }
}

// MARK: - Detail view

struct ScreenshotDetailView: View {
    let screenshot: Screenshot
    var siblings: [Screenshot]? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Screenshot.addedToLibraryDate, order: .reverse) private var allScreenshots: [Screenshot]
    @Query(sort: \ScreenshotTag.value, order: .forward) private var allTags: [ScreenshotTag]
    @Environment(\.dismiss) private var dismiss
    @State private var activeConfirmationModal: DetailConfirmationModal?
    @State private var isShowingTagEditor = false
    @State private var isShowingPuddleEditor = false
    @State private var scrollProgress: CGFloat = 0

    @State private var currentLocalIdentifier: String

    private var isShowingConfirmationAlert: Binding<Bool> {
        Binding(
            get: { activeConfirmationModal != nil },
            set: { if !$0 { activeConfirmationModal = nil } }
        )
    }

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

    private func markViewed(_ shot: Screenshot) {
        guard shot.isNew else { return }
        shot.isNew = false
        try? modelContext.save()
    }

    private func deleteFromPhotos() {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [currentScreenshot.localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            currentScreenshot.isDeletedFromPhotos = true
            return
        }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        } completionHandler: { success, _ in
            if success {
                DispatchQueue.main.async {
                    currentScreenshot.isDeletedFromPhotos = true
                }
            }
        }
    }

    private func createdDateString(for shot: Screenshot) -> String {
        let date = shot.creationDate ?? shot.addedToLibraryDate
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var menuAction: ScreenshotAction? {
        let openAIEntities = currentScreenshot.entities.filter { $0.source == "openai" }
        let mapsTypes: Set<EntityType> = [.restaurant, .venue, .hotel, .location]
        let musicTypes: Set<EntityType> = [.artist, .band, .album]

        if ContentType(rawValue: currentScreenshot.contentType ?? "") == .travel {
            let mapsQuery = openAIEntities
                .filter({ mapsTypes.contains(EntityType(rawValue: $0.entityType) ?? .other) })
                .max(by: { $0.confidence < $1.confidence })?.name
                ?? currentScreenshot.title
                ?? "Travel"
            return .openInMaps(query: mapsQuery)
        }

        if let raw = currentScreenshot.sourceURL,
           let url = URL(string: raw) {
            let enhanced = enhancedSocialURL(url, ocrText: currentScreenshot.ocrText ?? "") ?? url
            return .openURL(enhanced)
        }

        if let ocrText = currentScreenshot.ocrText,
           let url = firstURL(in: ocrText) {
            let enhanced = enhancedSocialURL(url, ocrText: ocrText) ?? url
            return .openURL(enhanced)
        }

        if let entity = openAIEntities
            .filter({ mapsTypes.contains(EntityType(rawValue: $0.entityType) ?? .other) })
            .max(by: { $0.confidence < $1.confidence }) {
            return .openInMaps(query: entity.name)
        }

        if let entity = openAIEntities
            .filter({ musicTypes.contains(EntityType(rawValue: $0.entityType) ?? .other) })
            .filter({ !MusicClientInfo.isClientName($0.name) })
            .max(by: { $0.confidence < $1.confidence }) {
            return .searchMusic(query: entity.name, client: currentScreenshot.musicClient)
        }

        let topEntity = openAIEntities.max(by: { $0.confidence < $1.confidence })

        switch ContentType(rawValue: currentScreenshot.contentType ?? "") {
        case .food, .travel, .architecture:
            let query = topEntity?.name ?? currentScreenshot.contentType ?? ""
            return query.isEmpty ? nil : .openInMaps(query: query)
        case .nature:
            guard let query = topEntity?.name, !query.isEmpty else { return nil }
            return .openInMaps(query: query)
        case .music:
            let query = topEntity?.name ?? ""
            return query.isEmpty ? nil : .searchMusic(query: query, client: currentScreenshot.musicClient)
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

    private func enhancedSocialURL(_ url: URL, ocrText: String) -> URL? {
        let socialHosts: Set<String> = [
            "instagram.com", "twitter.com", "x.com",
            "tiktok.com", "threads.net", "facebook.com"
        ]
        guard let host = url.host,
              socialHosts.contains(host),
              url.path.isEmpty || url.path == "/" else {
            return nil
        }

        if let handle = atHandle(in: ocrText) {
            return URL(string: "https://\(host)/\(handle)")
        }

        let username = currentScreenshot.entities
            .filter { $0.source == "openai" }
            .sorted { $0.confidence > $1.confidence }
            .compactMap { entity -> String? in
                let normalized = entity.normalizedName
                return (!normalized.contains(" ") && normalized.count <= 40) ? normalized : nil
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

    private func confirmActiveModalAction() {
        switch activeConfirmationModal {
        case .hideScreenshot:
            modelContext.delete(currentScreenshot)
            try? modelContext.save()
            activeConfirmationModal = nil
            dismiss()
        case .deleteFromPhotos:
            activeConfirmationModal = nil
            deleteFromPhotos()
        case nil:
            break
        }
    }

    private var currentPuddleName: String {
        ContentType(rawValue: currentScreenshot.contentType ?? "")?.displayName ?? "Unassigned"
    }

    var body: some View {
        TabView(selection: $currentLocalIdentifier) {
            ForEach(screenshots) { shot in
                ScreenshotPageView(screenshot: shot, scrollProgress: $scrollProgress)
                    .tag(shot.localIdentifier)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear { markViewed(currentScreenshot) }
        .onChange(of: currentLocalIdentifier) { markViewed(currentScreenshot) }
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
                Menu {
                    Section {
                        Button {
                            isShowingTagEditor = true
                        } label: {
                            Label("Edit tags", systemImage: "tag")
                        }
                        Button {
                            isShowingPuddleEditor = true
                        } label: {
                            Text("Change Puddle")
                            Text(currentPuddleName)
                            Image(systemName: "drop")
                        }

                        if let action = menuAction, let url = action.url {
                            Button {
                                openURL(url)
                            } label: {
                                Text(action.title)
                                Text(action.subtitle)
                                Image(systemName: action.icon)
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive) { activeConfirmationModal = .hideScreenshot } label: {
                            Label("Hide screenshot", systemImage: "eye.slash")
                        }
                        Button(role: .destructive) { activeConfirmationModal = .deleteFromPhotos } label: {
                            Label("Delete from Photos", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $isShowingTagEditor) {
            TagEditorSheet(
                screenshot: currentScreenshot,
                availableTagValues: Array(Set(allTags.map(\.value))).sorted()
            )
        }
        .sheet(isPresented: $isShowingPuddleEditor) {
            PuddleEditorSheet(screenshot: currentScreenshot)
        }
        .alert(
            activeConfirmationModal?.title ?? "",
            isPresented: isShowingConfirmationAlert,
            presenting: activeConfirmationModal
        ) { modal in
            Button(modal.confirmTitle, role: .destructive, action: confirmActiveModalAction)
            Button("Cancel", role: .cancel) {
                activeConfirmationModal = nil
            }
        } message: { modal in
            Text(modal.message)
        }
    }

}

private struct TagEditorSheet: View {
    let screenshot: Screenshot
    let availableTagValues: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var newTagText = ""

    private var sortedSelectedTags: [String] {
        Array(Set(screenshot.tags.map(\.value))).sorted()
    }

    private var normalizedNewTag: String {
        newTagText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var matchingTagSuggestions: [String] {
        guard !normalizedNewTag.isEmpty else { return [] }

        return availableTagValues
            .filter { !sortedSelectedTags.contains($0) }
            .filter { $0.localizedCaseInsensitiveContains(normalizedNewTag) }
            .prefix(8)
            .map { $0 }
    }

    private func hasTag(_ value: String) -> Bool {
        screenshot.tags.contains { $0.value == value }
    }

    private func addTag(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !hasTag(normalized) else { return }

        let tag = ScreenshotTag(value: normalized, source: "user")
        tag.screenshot = screenshot
        screenshot.tags.append(tag)
        try? modelContext.save()
    }

    private func removeTag(_ value: String) {
        guard let tag = screenshot.tags.first(where: { $0.value == value }) else { return }
        screenshot.tags.removeAll { $0 === tag }
        modelContext.delete(tag)
        try? modelContext.save()
    }

    private func addTypedTag() {
        addTag(normalizedNewTag)
        newTagText = ""
    }

    var body: some View {
        NavigationStack {
            List {
                Section("New Tag") {
                    HStack(spacing: 12) {
                        TextField("Add a tag", text: $newTagText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addTypedTag)

                        Button("Add") {
                            addTypedTag()
                        }
                        .disabled(normalizedNewTag.isEmpty || hasTag(normalizedNewTag))
                    }
                }

                if !matchingTagSuggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(matchingTagSuggestions, id: \.self) { tag in
                            Button {
                                addTag(tag)
                                newTagText = ""
                            } label: {
                                HStack {
                                    Text(tag)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "tag.fill")
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Current Tags") {
                    if sortedSelectedTags.isEmpty {
                        Text("No tags yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedSelectedTags, id: \.self) { tag in
                            Button {
                                removeTag(tag)
                            } label: {
                                HStack {
                                    Text(tag)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Edit tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PuddleEditorSheet: View {
    let screenshot: Screenshot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var availablePuddles: [ContentType] {
        ContentType.allCases.filter { $0 != .unknown }
    }

    private func assign(_ contentType: ContentType) {
        screenshot.contentType = contentType.rawValue
        try? modelContext.save()
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Existing Puddles") {
                    ForEach(availablePuddles, id: \.self) { puddle in
                        Button {
                            assign(puddle)
                        } label: {
                            HStack(spacing: 12) {
                                Label(puddle.displayName, systemImage: puddle.sfSymbol)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if screenshot.contentType == puddle.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Change Puddle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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

// MARK: - Full screen image viewer

private struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    private var currentScale: CGFloat { scale * magnifyBy }
    private var currentOffset: CGSize {
        CGSize(width: offset.width + dragOffset.width,
               height: offset.height + dragOffset.height)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(currentScale)
                .offset(currentOffset)
                .gesture(
                    MagnificationGesture()
                        .updating($magnifyBy) { value, state, _ in state = value }
                        .onEnded { value in
                            scale *= value
                            if scale < 1 {
                                withAnimation(.spring(response: 0.3)) {
                                    scale = 1
                                    offset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            if scale <= 1 && value.translation.height > 80 {
                                dismiss()
                            } else {
                                offset = CGSize(
                                    width: offset.width + value.translation.width,
                                    height: offset.height + value.translation.height
                                )
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        if scale > 1 {
                            scale = 1
                            offset = .zero
                        } else {
                            scale = 2
                        }
                    }
                }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .padding()
        }
    }
}


// MARK: - Per-screenshot page content

private struct ScreenshotPageView: View {
    let screenshot: Screenshot
    @Binding var scrollProgress: CGFloat

    @State private var image: UIImage? = nil
    @State private var viewportSize: CGSize = .zero
    @State private var isFullScreen = false
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
                    .onTapGesture { isFullScreen = true }
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
        .padding(.top, 84)
        .frame(maxWidth: .infinity, alignment: .center)
        .fullScreenCover(isPresented: $isFullScreen) {
            if let image { FullScreenImageView(image: image) }
        }
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
            let enhanced = enhancedSocialURL(url, ocrText: screenshot.ocrText ?? "") ?? url
            return .openURL(enhanced)
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

        // 4. Music entity (skip if the entity name is just the client app name)
        if let entity = openAIEntities
            .filter({ musicTypes.contains(EntityType(rawValue: $0.entityType) ?? .other) })
            .filter({ !MusicClientInfo.isClientName($0.name) })
            .max(by: { $0.confidence < $1.confidence }) {
            return .searchMusic(query: entity.name, client: screenshot.musicClient)
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
            return query.isEmpty ? nil : .searchMusic(query: query, client: screenshot.musicClient)
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

        // Asset deleted from Photos — fall back to cached image data
        guard let asset = result.firstObject else {
            if let data = screenshot.imageData, let uiImage = UIImage(data: data) {
                self.image = uiImage
            }
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

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
