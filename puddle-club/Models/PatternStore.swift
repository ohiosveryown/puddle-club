import SwiftData
import Foundation

// MARK: - Supporting value types

struct RecurringTheme: Codable {
    let theme: String
    let count: Int
    let firstSeen: String
    let lastSeen: String
    let examples: [String]
}

struct BehavioralPattern: Codable {
    let pattern: String
    let insight: String
}

struct PatternSummary: Codable {
    let contentType: String
    let summary: String
}

// MARK: - SwiftData model
// Complex arrays are stored as JSON strings to avoid SwiftData Codable cast failures.

@Model
final class PatternStore {
    var createdAt: Date
    var screenshotCount: Int
    var aestheticSignature: [String]

    // JSON-encoded backing stores
    private var recurringThemesJSON: String
    private var behavioralPatternsJSON: String
    private var patternSummariesJSON: String

    init(
        createdAt: Date = Date(),
        screenshotCount: Int = 0,
        recurringThemes: [RecurringTheme] = [],
        aestheticSignature: [String] = [],
        behavioralPatterns: [BehavioralPattern] = [],
        patternSummaries: [PatternSummary] = []
    ) {
        self.createdAt = createdAt
        self.screenshotCount = screenshotCount
        self.aestheticSignature = aestheticSignature
        self.recurringThemesJSON = Self.encode(recurringThemes)
        self.behavioralPatternsJSON = Self.encode(behavioralPatterns)
        self.patternSummariesJSON = Self.encode(patternSummaries)
    }

    // MARK: - Decoded accessors

    var recurringThemes: [RecurringTheme] {
        Self.decode(recurringThemesJSON)
    }

    var behavioralPatterns: [BehavioralPattern] {
        Self.decode(behavioralPatternsJSON)
    }

    var patternSummaries: [PatternSummary] {
        Self.decode(patternSummariesJSON)
    }

    // MARK: - Context helpers

    func summary(for contentType: String) -> String? {
        patternSummaries.first(where: { $0.contentType == contentType })?.summary
    }

    func context(for screenshot: Screenshot) -> String? {
        var parts: [String] = []

        if let summary = summary(for: screenshot.contentType ?? "") {
            parts.append(summary)
        }

        if let title = screenshot.title {
            if let recurring = recurringThemes.first(where: { $0.examples.contains(title) }) {
                parts.append("Part of a recurring theme: \(recurring.theme) — \(recurring.count) saves since \(recurring.firstSeen)")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    // MARK: - JSON helpers

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func decode<T: Decodable>(_ string: String) -> [T] {
        guard let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode([T].self, from: data) else { return [] }
        return value
    }
}
