import SwiftData
import Foundation

@Model
final class Screenshot {
    @Attribute(.unique) var localIdentifier: String
    var creationDate: Date?
    var addedToLibraryDate: Date
    var processingStatus: String
    var processingAttempts: Int
    var errorMessage: String?
    var ocrText: String?
    var ocrConfidence: Double
    var ocrWordCount: Int
    var screenshotMode: String?
    var title: String?
    var contentType: String?
    var reflection: String?
    var dominantColors: [String]
    var moodTags: [String]
    var aestheticNotes: [String]?
    var openAIProcessedAt: Date?
    var sourceURL: String?
    var musicClient: String?
    var isNew: Bool
    @Relationship(deleteRule: .cascade) var entities: [ScreenshotEntity]
    @Relationship(deleteRule: .cascade) var tags: [ScreenshotTag]

    init(localIdentifier: String, creationDate: Date? = nil, addedToLibraryDate: Date = Date()) {
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.addedToLibraryDate = addedToLibraryDate
        self.processingStatus = ProcessingStatus.pending.rawValue
        self.processingAttempts = 0
        self.ocrConfidence = 0.0
        self.ocrWordCount = 0
        self.dominantColors = []
        self.moodTags = []
        self.aestheticNotes = []
        self.entities = []
        self.tags = []
        self.isNew = true
    }
}

extension Screenshot {
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        if let contentType, !contentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return contentType
        }
        return String(localIdentifier.prefix(8))
    }
}
