import SwiftData
import Foundation

actor PatternService {

    // MARK: - Lightweight input type

    struct ScreenshotSummary: Encodable {
        let title: String
        let contentType: String
        let tags: [String]
        let aestheticNotes: [String]
        let moodTags: [String]
        let savedAt: String
    }

    // MARK: - Decoded response types

    private struct PatternResponse: Decodable {
        let recurringThemes: [RecurringThemeResponse]
        let aestheticSignature: [String]
        let behavioralPatterns: [BehavioralPatternResponse]
        let patternSummaries: [PatternSummaryResponse]
        let weeklyInsight: String

        struct RecurringThemeResponse: Decodable {
            let theme: String
            let count: Int
            let firstSeen: String
            let lastSeen: String
            let examples: [String]
        }

        struct BehavioralPatternResponse: Decodable {
            let pattern: String
            let insight: String
        }

        struct PatternSummaryResponse: Decodable {
            let contentType: String
            let summary: String
        }
    }

    // MARK: - Prompt

    private let patternPrompt = """
        You are analyzing a personal screenshot library to identify \
        taste patterns, recurring interests, and behavioral signals. \
        This data will be used to generate personalized reflections \
        that feel like they come from something that has been paying \
        close attention over time.

        Return ONLY valid JSON with these keys: \
        recurringThemes, aestheticSignature, behavioralPatterns, patternSummaries, weeklyInsight.

        RECURRING THEMES
        Array of {theme, count, firstSeen, lastSeen, examples[]}. \
        Identify topics, places, people, or content types that appear 3 or more times. \
        Be specific — not "beaches" but "empty coastlines, usually overcast, no people visible."

        AESTHETIC SIGNATURE
        Array of 3–5 phrases describing the user's overall visual taste across the library. \
        Should feel like a considered critical observation, not a list of tags. \
        Good: "Drawn to spaces that feel inhabited rather than designed. Prefers grain over polish." \
        Bad: "Likes minimalism, black and white, vintage"

        BEHAVIORAL PATTERNS
        Array of {pattern, insight}. \
        Observations about how and when they save, not just what.

        PATTERN SUMMARIES
        Array of {contentType, summary}. \
        For each major content type, a 1–2 sentence summary written in second person \
        that can be injected into individual reflections as context. \
        These should be specific enough to feel personal. \
        Good: "You save coastal destinations almost exclusively — specifically places that feel \
        uncrowded and slightly melancholy." \
        Bad: "You enjoy saving travel content including beaches and destinations."

        WEEKLY INSIGHT
        A single string. 2–3 sentences (max 5 words per sentence). Target 100-168 characters total. Second person. \
        A high-level observation about what the user has been saving recently — the dominant theme, \
        a pattern shift, or something specific that keeps recurring. \
        Vary the sentence structure — do NOT always start with "You" or "You saved". \
        Sometimes lead with the pattern itself (e.g. "Dense, text-forward interfaces keep showing up…"). \
        Tone: thoughtful, observational, like a perceptive friend noticing something about your taste. \
        Not a summary. Not a list. One cohesive thought. Keep the writing tight and avoid filler phrases like "this screenshot shows" or "it seems that" or "it's clear that".
        """

    // MARK: - Public

    func analyze(
        screenshots: [Screenshot],
        provider: AIProvider,
        modelContext: ModelContext
    ) async throws {
        let summaries = screenshots.compactMap { s -> ScreenshotSummary? in
            guard let contentType = s.contentType, !contentType.isEmpty else { return nil }
            let formatter = ISO8601DateFormatter()
            return ScreenshotSummary(
                title: s.title ?? s.displayTitle,
                contentType: contentType,
                tags: s.tags.map { $0.value },
                aestheticNotes: s.aestheticNotes ?? [],
                moodTags: s.moodTags,
                savedAt: formatter.string(from: s.addedToLibraryDate)
            )
        }

        guard !summaries.isEmpty else { return }

        let inputJSON = try JSONEncoder().encode(summaries)
        let inputString = String(data: inputJSON, encoding: .utf8) ?? "[]"
        let userMessage = "Screenshot library:\n\(inputString)"

        let response: PatternResponse = try await provider == .anthropic
            ? callAnthropic(userMessage: userMessage)
            : callOpenAI(userMessage: userMessage)

        let store = PatternStore(
            createdAt: Date(),
            screenshotCount: screenshots.count,
            recurringThemes: response.recurringThemes.map {
                RecurringTheme(theme: $0.theme, count: $0.count,
                               firstSeen: $0.firstSeen, lastSeen: $0.lastSeen,
                               examples: $0.examples)
            },
            aestheticSignature: response.aestheticSignature,
            behavioralPatterns: response.behavioralPatterns.map {
                BehavioralPattern(pattern: $0.pattern, insight: $0.insight)
            },
            patternSummaries: response.patternSummaries.map {
                PatternSummary(contentType: $0.contentType, summary: $0.summary)
            },
            weeklyInsight: response.weeklyInsight
        )

        // Replace any existing store (keep only the latest)
        let existing = try modelContext.fetch(FetchDescriptor<PatternStore>())
        for old in existing { modelContext.delete(old) }
        modelContext.insert(store)
        try modelContext.save()
    }

    // MARK: - Private API calls

    private func callAnthropic(userMessage: String) async throws -> PatternResponse {
        let apiKey = try KeychainService.loadAnthropicAPIKey()
        let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "temperature": 0,
            "system": patternPrompt,
            "messages": [["role": "user", "content": userMessage]]
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let contentArray = json?["content"] as? [[String: Any]],
              var text = contentArray.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { throw PatternError.malformedResponse }

        text = stripMarkdownFences(text)
        return try JSONDecoder().decode(PatternResponse.self, from: Data(text.utf8))
    }

    private func callOpenAI(userMessage: String) async throws -> PatternResponse {
        let apiKey = try KeychainService.loadAPIKey()
        let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!

        let body: [String: Any] = [
            "model": "gpt-4.1",
            "response_format": ["type": "json_object"],
            "temperature": 0,
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": patternPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              var text = choices.first?["message"] as? [String: Any],
              let content = text["content"] as? String
        else { throw PatternError.malformedResponse }

        let stripped = stripMarkdownFences(content)
        return try JSONDecoder().decode(PatternResponse.self, from: Data(stripped.utf8))
    }

    private func stripMarkdownFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum PatternError: Error {
        case malformedResponse
    }
}
