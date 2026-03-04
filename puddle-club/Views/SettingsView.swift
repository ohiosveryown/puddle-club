import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var openAIStatus: String? = nil
    @State private var anthropicStatus: String? = nil
    @State private var reprocessStatus: String? = nil
    @State private var isValidatingOpenAI: Bool = false
    @State private var isValidatingAnthropic: Bool = false
    @AppStorage("aiProvider") private var aiProvider: String = AIProvider.openai.rawValue

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $aiProvider) {
                    Text("OpenAI").tag(AIProvider.openai.rawValue)
                    Text("Anthropic").tag(AIProvider.anthropic.rawValue)
                }
                .pickerStyle(.segmented)
            }

            Section("OpenAI API Key") {
                SecureField("sk-…", text: $openAIKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Save Key") { saveOpenAIKey() }

                Button("Validate Key") {
                    Task { await validateOpenAIKey() }
                }
                .disabled(isValidatingOpenAI)

                if let msg = openAIStatus {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.lowercased().contains("error") ? Color.red : Color.green)
                }
            }

            Section {
                Button("Delete OpenAI Key", role: .destructive) { deleteOpenAIKey() }
            }

            Section("Anthropic API Key") {
                SecureField("sk-ant-…", text: $anthropicKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Save Key") { saveAnthropicKey() }

                Button("Validate Key") {
                    Task { await validateAnthropicKey() }
                }
                .disabled(isValidatingAnthropic)

                if let msg = anthropicStatus {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.lowercased().contains("error") ? Color.red : Color.green)
                }
            }

            Section {
                Button("Delete Anthropic Key", role: .destructive) { deleteAnthropicKey() }
            }

            Section("Data") {
                Button("Reprocess All Screenshots") { Task { await reprocessAll() } }

                if let msg = reprocessStatus {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.lowercased().contains("error") ? Color.red : Color.green)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { loadExistingKeys() }
    }

    private func loadExistingKeys() {
        openAIKey = (try? KeychainService.loadAPIKey()) ?? ""
        anthropicKey = (try? KeychainService.loadAnthropicAPIKey()) ?? ""
    }

    private func saveOpenAIKey() {
        do {
            try KeychainService.saveAPIKey(openAIKey)
            openAIStatus = "Key saved"
        } catch {
            openAIStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func validateOpenAIKey() async {
        isValidatingOpenAI = true
        defer { isValidatingOpenAI = false }
        do {
            let trimmed = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            openAIKey = trimmed
            try KeychainService.saveAPIKey(trimmed)
            let valid = try await OpenAIService().validateAPIKey()
            openAIStatus = valid ? "Key is valid ✓" : "Validation failed"
        } catch {
            openAIStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func deleteOpenAIKey() {
        do {
            try KeychainService.deleteAPIKey()
            openAIKey = ""
            openAIStatus = "Key deleted"
        } catch {
            openAIStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func saveAnthropicKey() {
        do {
            try KeychainService.saveAnthropicAPIKey(anthropicKey)
            anthropicStatus = "Key saved"
        } catch {
            anthropicStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func validateAnthropicKey() async {
        isValidatingAnthropic = true
        defer { isValidatingAnthropic = false }
        do {
            let trimmed = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            anthropicKey = trimmed
            try KeychainService.saveAnthropicAPIKey(trimmed)
            let valid = try await AnthropicService().validateAPIKey()
            anthropicStatus = valid ? "Key is valid ✓" : "Validation failed"
        } catch {
            anthropicStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func deleteAnthropicKey() {
        do {
            try KeychainService.deleteAnthropicAPIKey()
            anthropicKey = ""
            anthropicStatus = "Key deleted"
        } catch {
            anthropicStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func reprocessAll() async {
        do {
            let pipeline = ProcessingPipeline(
                container: modelContext.container,
                state: PipelineState(),
                provider: AIProvider(rawValue: aiProvider) ?? .openai
            )
            try await pipeline.resetAllForReprocessing()
            reprocessStatus = "Ready — tap Process on the home screen"
        } catch {
            reprocessStatus = "Error: \(error.localizedDescription)"
        }
    }
}
