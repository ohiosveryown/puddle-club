import SwiftUI
import SwiftData
import Photos

struct GroupDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let type: ContentType
    let screenshots: [Screenshot]

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

        for screenshot in screenshots {
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
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let colWidth = (geo.size.width - spacing * 3) / 2
            let cols = columns(colWidth: colWidth, spacing: spacing)

            ScrollView {
                HStack(alignment: .top, spacing: spacing) {
                    masonryColumn(columnItems: cols.left, colWidth: colWidth, spacing: spacing)
                    masonryColumn(columnItems: cols.right, colWidth: colWidth, spacing: spacing)
                }
                .padding(spacing)
            }
            .contentMargins(.bottom, 80, for: .scrollContent)
        }
        .onAppear { markAllViewed() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 3) {
                    Text(type.displayName)
                        .font(.headline)
                    Text("\(screenshots.count.formatted()) images")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func markAllViewed() {
        var changed = false
        for s in screenshots where s.isNew {
            s.isNew = false
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    @ViewBuilder
    private func masonryColumn(columnItems: [Screenshot], colWidth: CGFloat, spacing: CGFloat) -> some View {
        LazyVStack(spacing: spacing) {
            ForEach(columnItems) { screenshot in
                let h = cellHeight(for: screenshot, colWidth: colWidth)
                NavigationLink(destination: ScreenshotDetailView(screenshot: screenshot, siblings: screenshots)) {
                    MasonryImageCell(screenshot: screenshot, width: colWidth, clipHeight: h)
                }
                .buttonStyle(.plain)
                .contextMenu { deleteButton(for: screenshot) }
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
}


// MARK: - Masonry Image Cell

private struct MasonryImageCell: View {
    let screenshot: Screenshot
    let width: CGFloat
    var clipHeight: CGFloat? = nil
    @State private var image: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.32)
            : Color.black.opacity(0.10)
    }

    private var height: CGFloat { clipHeight ?? (width / 0.46) }

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
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(borderColor, lineWidth: 0.5))
        .onAppear(perform: loadImage)
    }

    private func loadImage() {
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
            targetSize: CGSize(width: 500, height: 1000),
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
