import Foundation

actor AnthropicService {
    private let textModel = "claude-sonnet-4-6"
    private let visionModel = "claude-opus-4-6"
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    private let systemPrompt = """
        Return ONLY valid JSON with keys: title, contentType, contentTypeConfidence, \
        entities [{name, type, confidence}], tags, reflection, dominantColors, moodTags, aestheticNotes. \
        title should be a concise name for the subject (e.g. "Carlsbad Flower Fields", "Kendrick Lamar", "Nike Air Max 90"). \
        contentType must be exactly one of: food, music, travel, design, fashion, product, architecture, art, text, social, event, person, nature, woodworking, unknown. \
        reflection should be 1–2 sentences, written directly to the user in the second person ("you"), \
        as a personal, reflective note about why this screenshot might matter to them or how it fits into their life. \
        Focus on mood and the user's relationship to the content, not a dry summary of what's on screen. \
        aestheticNotes should be an array of 1–4 short phrases (e.g. "1980s film", "Organic forms", \
        "Art book layout energy", "Museum-catalog feel") that describe the overall aesthetic and visual/typographic vibe, \
        based on the image and any OCR text.
        """

    func classifyText(ocrText: String, nlpEntities: [RawEntity]) async throws -> OpenAIClassificationResult {
        let apiKey = try KeychainService.loadAnthropicAPIKey()

        let userContent = """
            OCR Text: \(ocrText)

            NLP Entity Hints: \(encodeEntities(nlpEntities))
            """

        let body: [String: Any] = [
            "model": textModel,
            "max_tokens": 512,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        return try await performRequest(body: body, apiKey: apiKey)
    }

    func classifyImage(imageData: Data, ocrText: String?) async throws -> OpenAIClassificationResult {
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
            "max_tokens": 512,
            "system": systemPrompt,
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
