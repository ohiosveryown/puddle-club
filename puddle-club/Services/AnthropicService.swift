import Foundation

actor AnthropicService {
    private let textModel = "claude-sonnet-4-6"
    private let visionModel = "claude-opus-4-6"
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

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
        let apiKey = try KeychainService.loadAnthropicAPIKey()

        let userContent = """
            OCR Text: \(ocrText)

            NLP Entity Hints: \(encodeEntities(nlpEntities))
            """

        let body: [String: Any] = [
            "model": textModel,
            "max_tokens": 1024,
            "temperature": 0,
            "system": intakePrompt(patternContext: patternContext),
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        return try await performRequest(body: body, apiKey: apiKey)
    }

    func classifyImage(imageData: Data, ocrText: String?, patternContext: String? = nil) async throws -> OpenAIClassificationResult {
        let apiKey = try KeychainService.loadAnthropicAPIKey()
        let base64 = imageData.base64EncodedString()

        var contentItems: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64
                ]
            ]
        ]

        if let ocrText, !ocrText.isEmpty {
            contentItems.append(["type": "text", "text": "OCR Text: \(ocrText)"])
        }

        let body: [String: Any] = [
            "model": visionModel,
            "max_tokens": 1024,
            "temperature": 0,
            "system": intakePrompt(patternContext: patternContext),
            "messages": [
                ["role": "user", "content": contentItems]
            ]
        ]

        return try await performRequest(body: body, apiKey: apiKey)
    }

    func validateAPIKey() async throws -> Bool {
        let apiKey = try KeychainService.loadAnthropicAPIKey()
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": textModel,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw AnthropicError.apiError(http.statusCode, body)
        }
        return true
    }

    // MARK: - Private

    private func performRequest(body: [String: Any], apiKey: String) async throws -> OpenAIClassificationResult {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnthropicError.apiError(http.statusCode, body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let contentArray = json?["content"] as? [[String: Any]],
              var text = contentArray.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
            throw AnthropicError.malformedResponse
        }

        text = stripMarkdownFences(text)

        guard let contentData = text.data(using: .utf8) else {
            throw AnthropicError.malformedResponse
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

    enum AnthropicError: Error, LocalizedError {
        case invalidResponse
        case apiError(Int, String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid HTTP response"
            case .apiError(let code, let body): return "API error \(code): \(body)"
            case .malformedResponse: return "Malformed response from Anthropic"
            }
        }
    }
}
