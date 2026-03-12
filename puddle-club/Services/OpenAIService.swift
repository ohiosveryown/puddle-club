import Foundation

struct OpenAIClassificationResult: Sendable, Decodable {
    let title: String
    let contentType: String
    let contentTypeConfidence: Double
    let entities: [OpenAIEntity]
    let tags: [String]
    let reflection: String
    let dominantColors: [String]
    let moodTags: [String]
    let aestheticNotes: [String]
    let sourceURL: String?
    let musicClient: String?

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        contentType = (try? c.decodeIfPresent(String.self, forKey: .contentType)) ?? "unknown"
        contentTypeConfidence = (try? c.decodeIfPresent(Double.self, forKey: .contentTypeConfidence)) ?? 0.0
        entities = (try? c.decodeIfPresent([OpenAIEntity].self, forKey: .entities)) ?? []
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        reflection = (try? c.decodeIfPresent(String.self, forKey: .reflection)) ?? ""
        dominantColors = (try? c.decodeIfPresent([String].self, forKey: .dominantColors)) ?? []
        moodTags = (try? c.decodeIfPresent([String].self, forKey: .moodTags)) ?? []
        aestheticNotes = (try? c.decodeIfPresent([String].self, forKey: .aestheticNotes)) ?? []
        sourceURL = try? c.decodeIfPresent(String.self, forKey: .sourceURL)
        musicClient = try? c.decodeIfPresent(String.self, forKey: .musicClient)
    }

    private enum CodingKeys: String, CodingKey {
        case title, contentType, contentTypeConfidence, entities, tags
        case reflection, dominantColors, moodTags, aestheticNotes, sourceURL, musicClient
    }
}

struct OpenAIEntity: Sendable, Decodable {
    let name: String
    let type: String
    let confidence: Double

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(String.self, forKey: .type)
        confidence = try c.decode(Double.self, forKey: .confidence)
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, confidence
    }
}

actor OpenAIService {
    // model
    private let textModel = "gpt-4.1-mini"
    private let visionModel = "gpt-4.1"
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    private func intakePrompt(patternContext: String?) -> String {
        """
        Return ONLY valid JSON with keys: title, contentType, contentTypeConfidence, \
        entities [{name, type, confidence}], tags, reflection, dominantColors, moodTags, aestheticNotes, sourceURL, musicClient.

        TITLE: A concise name for the subject. Be specific. \
        Good: "Carlsbad Flower Fields", "Kendrick Lamar - GNX", "Nike Air Max 90". \
        Bad: "Beautiful landscape", "Music album", "Sneaker".

        CONTENT TYPE: Must be exactly one of: food, music, travel, design, fashion, product, \
        architecture, art, text, social, event, person, nature, woodworking, unknown. \
        contentTypeConfidence: 0.0–1.0.

        ENTITIES: Array of {name, type, confidence} for identifiable people, places, brands, songs, dishes, etc.

        TAGS: 3–6 short descriptive keywords. Factual, not aesthetic.

        REFLECTION: 1–2 sentences. Second person ("you"). \
        Focus on mood and the user's relationship to this content — not a description of what's on screen. \
        Vary the sentence structure — do NOT always start with "You" or "You saved". \
        Sometimes begin with the pattern or theme itself (e.g. "Dense, text-forward interfaces keep showing up in your saves…"). \
        The tone should feel like a thoughtful observation from a perceptive friend, not a classifier. \
        If pattern context is provided below, reference it directly and specifically. \
        If no pattern context, keep it observational and open.

        AESTHETIC NOTES: Array of 1–2 short phrases (max 3 words per phrase) describing the overall visual, typographic, and tonal vibe. \
        Good: "1980s film", "Organic forms", "Art book energy". \
        Only include if genuinely distinctive — omit for generic imagery.

        MOOD TAGS: Array of 2–4 single words describing the emotional register. \
        Good: "Melancholy", "Aspirational", "Playful", "Quiet". Different from aestheticNotes — about feeling, not visual style.

        SOURCE URL: Most relevant URL visible anywhere in the image (address bar, footer, watermark, caption, etc.). \
        Social posts: prefer direct post URL (e.g. "https://x.com/user/status/123"). \
        If only a handle is visible: return profile URL (e.g. "https://instagram.com/username"). \
        Any other site: return domain as-is. Omit if no URL present.

        MUSIC CLIENT: Only for music content. The streaming app visible in the screenshot. \
        Must be exactly one of: spotify, apple_music, youtube_music, tidal, soundcloud, amazon_music, podcasts. \
        Detect from UI: Spotify's dark UI with green accents, Apple Music's red/dark UI, \
        YouTube Music's black UI with red accents, etc. \
        Omit this key entirely if contentType is not music, or if the app cannot be determined.

        ---
        PATTERN CONTEXT (injected at runtime if available):
        \(patternContext ?? "None available — treat this as a first impression.")
        """
    }

    func classifyText(ocrText: String, nlpEntities: [RawEntity], patternContext: String? = nil) async throws -> OpenAIClassificationResult {
        let apiKey = try KeychainService.loadAPIKey()

        let userContent = """
            OCR Text: \(ocrText)

            NLP Entity Hints: \(encodeEntities(nlpEntities))
            """

        let body: [String: Any] = [
            "model": textModel,
            "response_format": ["type": "json_object"],
            "temperature": 0,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": intakePrompt(patternContext: patternContext)],
                ["role": "user", "content": userContent]
            ]
        ]

        return try await performRequest(body: body, apiKey: apiKey)
    }

    func classifyImage(imageData: Data, ocrText: String?, patternContext: String? = nil) async throws -> OpenAIClassificationResult {
        let apiKey = try KeychainService.loadAPIKey()
        let base64 = imageData.base64EncodedString()

        var userContent: [[String: Any]] = [
            [
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)",
                    "detail": "low"
                ]
            ]
        ]

        if let ocrText, !ocrText.isEmpty {
            userContent.append(["type": "text", "text": "OCR Text: \(ocrText)"])
        }

        let body: [String: Any] = [
            "model": visionModel,
            "response_format": ["type": "json_object"],
            "temperature": 0,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": intakePrompt(patternContext: patternContext)],
                ["role": "user", "content": userContent]
            ]
        ]

        return try await performRequest(body: body, apiKey: apiKey)
    }

    func validateAPIKey() async throws -> Bool {
        let apiKey = try KeychainService.loadAPIKey()
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": textModel,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // MARK: - Private

    private func performRequest(body: [String: Any], apiKey: String) async throws -> OpenAIClassificationResult {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.apiError(http.statusCode, body)
        }

        // Unwrap chat completion envelope
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              var content = message["content"] as? String else {
            throw OpenAIError.malformedResponse
        }

        content = stripMarkdownFences(content)

        guard let contentData = content.data(using: .utf8) else {
            throw OpenAIError.malformedResponse
        }

        return try JSONDecoder().decode(OpenAIClassificationResult.self, from: contentData)
    }

    private func stripMarkdownFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func encodeEntities(_ entities: [RawEntity]) -> String {
        let mapped = entities.map { ["text": $0.text, "type": $0.type] }
        guard let data = try? JSONSerialization.data(withJSONObject: mapped),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    enum OpenAIError: Error, LocalizedError {
        case invalidResponse
        case apiError(Int, String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid HTTP response"
            case .apiError(let code, let body): return "API error \(code): \(body)"
            case .malformedResponse: return "Malformed response from OpenAI"
            }
        }
    }
}
