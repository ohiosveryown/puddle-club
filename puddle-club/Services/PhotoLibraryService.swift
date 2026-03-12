import Photos
import UIKit

struct ScreenshotFetchResult: Sendable {
    let localIdentifier: String
    let creationDate: Date?
    let addedToLibraryDate: Date
}

/// Ensures a CheckedContinuation is resumed at most once, even when the
/// underlying callback fires multiple times (e.g. PHImageManager degraded + full-res).
private final class OnceContinuation<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    func set(_ continuation: CheckedContinuation<T, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func resume(returning value: T) {
        lock.withLock {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    func resume(throwing error: Error) {
        lock.withLock {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

actor PhotoLibraryService {

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func fetchNewScreenshotIdentifiers(excluding knownIdentifiers: Set<String>) async throws -> [ScreenshotFetchResult] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaSubtype & %d != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        // Process screenshots in the order they were created (oldest first)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var results: [ScreenshotFetchResult] = []

        assets.enumerateObjects { asset, _, _ in
            guard !knownIdentifiers.contains(asset.localIdentifier) else { return }
            results.append(ScreenshotFetchResult(
                localIdentifier: asset.localIdentifier,
                creationDate: asset.creationDate,
                addedToLibraryDate: Date()
            ))
        }

        return results
    }

    func fetchCompressedImageData(for localIdentifier: String, targetSize: CGFloat = 1024) async throws -> Data {
        try await fetchImageData(for: localIdentifier, size: CGSize(width: targetSize, height: targetSize), compressionQuality: 0.8)
    }

    func fetchHighResImageData(for localIdentifier: String) async throws -> Data {
        try await fetchImageData(for: localIdentifier, size: CGSize(width: 1568, height: 1568), compressionQuality: 0.7)
    }

    // MARK: - Private

    private func fetchImageData(for localIdentifier: String, size: CGSize, compressionQuality: CGFloat) async throws -> Data {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            throw PhotoLibraryError.assetNotFound(localIdentifier)
        }

        // Wrap in OnceContinuation — PHImageManager can fire its callback more than once
        // (e.g. degraded placeholder + full-res, or cancel path). Resuming a
        // CheckedContinuation twice is a hard crash, so we guard against it.
        let once = OnceContinuation<Data>()
        return try await withCheckedThrowingContinuation { continuation in
            once.set(continuation)

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.resizeMode = .exact
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                if isDegraded { return }

                if let error = info?[PHImageErrorKey] as? NSError {
                    if error.domain == "com.apple.accounts" {
                        once.resume(throwing: PhotoLibraryError.iCloudUnavailable)
                    } else {
                        once.resume(throwing: error)
                    }
                } else if let image, let data = image.jpegData(compressionQuality: compressionQuality) {
                    once.resume(returning: data)
                } else {
                    once.resume(throwing: PhotoLibraryError.imageDataUnavailable)
                }
            }
        }
    }

    enum PhotoLibraryError: Error, LocalizedError {
        case assetNotFound(String)
        case imageDataUnavailable
        case iCloudUnavailable

        var errorDescription: String? {
            switch self {
            case .assetNotFound(let id): return "Asset not found: \(id)"
            case .imageDataUnavailable: return "Image data unavailable"
            case .iCloudUnavailable: return "Photo is only available in iCloud and could not be downloaded"
            }
        }
    }
}
