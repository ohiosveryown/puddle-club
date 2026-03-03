import Vision
import NaturalLanguage
import UIKit

struct OCRResult: Sendable {
    let text: String
    let confidence: Double
    let wordCount: Int
    let boundingBoxCoverage: Double
}

struct RawEntity: Sendable, Codable {
    let text: String
    let type: String
}

actor OCRService {

    func extractText(from imageData: Data) async throws -> OCRResult {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw OCRError.invalidImageData
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                var lines: [String] = []
                var totalConfidence: Double = 0
                var boundingBoxArea: CGFloat = 0

                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    lines.append(candidate.string)
                    totalConfidence += Double(candidate.confidence)
                    let box = obs.boundingBox
                    boundingBoxArea += box.width * box.height
                }

                let fullText = lines.joined(separator: " ")
                let wordCount = fullText.split(separator: " ").count
                let avgConfidence = observations.isEmpty ? 0.0 : totalConfidence / Double(observations.count)

                continuation.resume(returning: OCRResult(
                    text: fullText,
                    confidence: avgConfidence,
                    wordCount: wordCount,
                    boundingBoxCoverage: Double(boundingBoxArea)
                ))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // nonisolated — pure NLP computation, no actor state accessed
    nonisolated func extractEntities(from text: String) -> [RawEntity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var entities: [RawEntity] = []

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        let recognizedTags: [NLTag] = [.personalName, .placeName, .organizationName]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard let tag, recognizedTags.contains(tag) else { return true }
            let entityText = String(text[range])
            let type: String
            switch tag {
            case .personalName: type = "person"
            case .placeName: type = "location"
            case .organizationName: type = "brand"
            default: type = "other"
            }
            entities.append(RawEntity(text: entityText, type: type))
            return true
        }

        return entities
    }

    // nonisolated — pure threshold logic, no actor state accessed
    nonisolated func classifyMode(result: OCRResult) -> ScreenshotMode {
        if result.wordCount > 20 && result.confidence > 0.6 && result.boundingBoxCoverage > 0.15 {
            return .textRich
        }
        return .imageDominant
    }

    enum OCRError: Error, LocalizedError {
        case invalidImageData
        var errorDescription: String? { "Invalid image data for OCR" }
    }
}
