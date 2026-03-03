import Foundation

enum ProcessingStatus: String, Codable, CaseIterable {
    case pending
    case ocrInProgress
    case ocrComplete
    case openAIInProgress
    case complete
    case failed
    case skipped
}

enum ContentType: String, Codable, CaseIterable {
    case food
    case music
    case travel
    case design
    case fashion
    case product
    case architecture
    case art
    case text
    case social
    case event
    case person
    case nature
    case unknown
}

enum ScreenshotMode: String, Codable {
    case textRich
    case imageDominant
}

enum EntityType: String, Codable, CaseIterable {
    case restaurant
    case venue
    case artist
    case band
    case hotel
    case brand
    case location
    case person
    case product
    case book
    case film
    case album
    case other
}
