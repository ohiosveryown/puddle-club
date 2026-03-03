import SwiftData
import Foundation

@Model
final class ScreenshotTag {
    var value: String
    var source: String
    var screenshot: Screenshot?

    init(value: String, source: String) {
        self.value = value.lowercased()
        self.source = source
    }
}
