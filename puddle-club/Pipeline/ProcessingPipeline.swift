import SwiftData
import Foundation
import Observation
import Photos

@Observable
@MainActor
final class PipelineState {
    var isProcessing: Bool = false
    var currentPhase: String = ""
    var totalCount: Int = 0
    var processedCount: Int = 0
    var errorMessage: String? = nil

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(processedCount) / Double(totalCount)
    }
}

enum AIProvider: String {
    case openai
    case anthropic
}

actor ProcessingPipeline {
    private let container: ModelContainer
    private let photoService: PhotoLibraryService
    private let openAIService: OpenAIService
    private let anthropicService: AnthropicService
    private let modelContext: ModelContext
    private let state: PipelineState
    private let provider: AIProvider

    init(container: ModelContainer, state: PipelineState, provider: AIProvider = .openai) {
        self.container = container
        self.state = state
        self.provider = provider
        self.photoService = PhotoLibraryService()
        self.openAIService = OpenAIService()
        self.anthropicService = AnthropicService()
        self.modelContext = ModelContext(container)
    }

    func run() async {
        await MainActor.run {
            state.isProcessing = true
            state.errorMessage = nil
            state.processedCount = 0
            state.totalCount = 0
        }
        defer { Task { @MainActor in self.state.isProcessing = false } }

        do {
            // Step 1: Authorization
            await updatePhase("Requesting photo access…")
            let authStatus = await photoService.requestAuthorization()
            guard authStatus == .authorized || authStatus == .limited else {
                await MainActor.run { state.errorMessage = "Photo library access denied." }
                return
            }

            // Step 2: Fetch new screenshots
            await updatePhase("Checking library…")
            let existingIDs = try fetchExistingIdentifiers()
            let newResults = try await photoService.fetchNewScreenshotIdentifiers(excluding: existingIDs)

            guard !newResults.isEmpty else {
                await updatePhase("No new screenshots found.")
                return
            }

            for result in newResults {
                let screenshot = Screenshot(
                    localIdentifier: result.localIdentifier,
                    creationDate: result.creationDate,
                    addedToLibraryDate: result.addedToLibraryDate
                )
                modelContext.insert(screenshot)
            }
            try modelContext.save()

            // Step 3: AI classification (sliding window, max 3 concurrent)
            // Include pending, ocrComplete (legacy), and failed for retry
            let unprocessedIDs = try [ProcessingStatus.pending, .ocrComplete, .failed]
                .flatMap { try fetchIdentifiers(withStatus: $0) }
            await MainActor.run {
                state.totalCount = unprocessedIDs.count
                state.processedCount = 0
            }
            await updatePhase("Classifying with AI…")

            try await processWithAI(identifiers: unprocessedIDs)

            // Step 4: Schedule background run
            BackgroundTaskManager.scheduleNextRun()
            await updatePhase("Complete")

        } catch {
            await MainActor.run { state.errorMessage = error.localizedDescription }
        }
    }

    // MARK: - Private helpers

    private func updatePhase(_ phase: String) async {
        await MainActor.run { state.currentPhase = phase }
    }

    func resetAllForReprocessing() throws {
        let all = try modelContext.fetch(FetchDescriptor<Screenshot>())
        for screenshot in all {
            let status = ProcessingStatus(rawValue: screenshot.processingStatus) ?? .pending
            if status == .complete || status == .failed || status == .skipped {
                screenshot.processingStatus = ProcessingStatus.pending.rawValue
                screenshot.processingAttempts = 0
                screenshot.errorMessage = nil
            }
        }
        try modelContext.save()
    }

    private func fetchExistingIdentifiers() throws -> Set<String> {
        let screenshots = try modelContext.fetch(FetchDescriptor<Screenshot>())
        return Set(screenshots.map { $0.localIdentifier })
    }

    private func fetchIdentifiers(withStatus status: ProcessingStatus) throws -> [String] {
        let value = status.rawValue
        let descriptor = FetchDescriptor<Screenshot>(
            predicate: #Predicate { $0.processingStatus == value }
        )
        return try modelContext.fetch(descriptor).map { $0.localIdentifier }
    }

    private func processWithAI(identifiers: [String]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = identifiers.makeIterator()

            for _ in 0..<min(3, identifiers.count) {
                if let id = iterator.next() {
                    group.addTask { try await self.processOpenAI(for: id) }
                }
            }

            while try await group.next() != nil {
                try modelContext.save()
                await MainActor.run { state.processedCount += 1 }

                if let id = iterator.next() {
                    group.addTask { try await self.processOpenAI(for: id) }
                }
            }
        }
    }

    private func processOpenAI(for identifier: String) async throws {
        let descriptor = FetchDescriptor<Screenshot>(
            predicate: #Predicate { $0.localIdentifier == identifier }
        )
        guard let screenshot = try modelContext.fetch(descriptor).first else { return }

        let maxAttempts = 3

        while screenshot.processingAttempts < maxAttempts {
            screenshot.processingStatus = ProcessingStatus.openAIInProgress.rawValue
            screenshot.processingAttempts += 1

            do {
                let imageData = try await photoService.fetchHighResImageData(for: identifier)
                let result = try await provider == .anthropic
                    ? anthropicService.classifyImage(imageData: imageData, ocrText: nil)
                    : openAIService.classifyImage(imageData: imageData, ocrText: nil)

                // Map result → model
                screenshot.title = generateTitle(from: result, for: screenshot)
                screenshot.contentType = result.contentType
                screenshot.reflection = result.reflection
                screenshot.dominantColors = result.dominantColors
                screenshot.moodTags = result.moodTags
                screenshot.aestheticNotes = result.aestheticNotes
                screenshot.sourceURL = result.sourceURL
                screenshot.openAIProcessedAt = Date()
                screenshot.processingStatus = ProcessingStatus.complete.rawValue

                // Replace stale entities and tags
                for old in screenshot.entities { modelContext.delete(old) }
                for entity in result.entities {
                    let record = ScreenshotEntity(
                        name: entity.name,
                        entityType: entity.type,
                        confidence: entity.confidence,
                        source: "openai"
                    )
                    record.screenshot = screenshot
                    modelContext.insert(record)
                }
                for old in screenshot.tags { modelContext.delete(old) }
                for tag in result.tags {
                    let record = ScreenshotTag(value: tag, source: "openai")
                    record.screenshot = screenshot
                    modelContext.insert(record)
                }
                return

            } catch {
                if screenshot.processingAttempts < maxAttempts {
                    let delay = pow(2.0, Double(screenshot.processingAttempts))
                    try await Task.sleep(for: .seconds(delay))
                } else {
                    screenshot.processingStatus = ProcessingStatus.failed.rawValue
                    screenshot.errorMessage = error.localizedDescription
                    return
                }
            }
        }

        screenshot.processingStatus = ProcessingStatus.skipped.rawValue
    }

    // MARK: - Title generation

    private func generateTitle(from result: OpenAIClassificationResult, for screenshot: Screenshot) -> String {
        if let existing = screenshot.title, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }

        let trimmedTitle = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }

        if let type = ContentType(rawValue: result.contentType) {
            return type.rawValue.capitalized
        }

        return "Screenshot"
    }
}
