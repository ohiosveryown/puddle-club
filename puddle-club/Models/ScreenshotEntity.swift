import SwiftData
import Foundation

@Model
final class ScreenshotEntity {
    var name: String
    var entityType: String
    var normalizedName: String
    var confidence: Double
    var source: String
    var screenshot: Screenshot?

    init(name: String, entityType: String, confidence: Double, source: String) {
        self.name = name
        self.entityType = entityType
        self.normalizedName = name.lowercased()
        self.confidence = confidence
        self.source = source
    }
}
