import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var statusMessage: String? = nil
    @State private var isValidating: Bool = false

    var body: some View {
        Form {
            Section("OpenAI API Key") {
                SecureField("sk-…", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Save Key") { saveKey() }

                Button("Validate Key") {
                    Task { await validateKey() }
                }
                .disabled(isValidating)

                if let msg = statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.lowercased().contains("error") ? Color.red : Color.green)
                }
            }

            Section {
                Button("Delete API Key", role: .destructive) { deleteKey() }
            }
        }
        .navigationTitle("Settings")
        .onAppear { loadExistingKey() }
    }

    private func loadExistingKey() {
        apiKey = (try? KeychainService.loadAPIKey()) ?? ""
    }

    private func saveKey() {
        do {
            try KeychainService.saveAPIKey(apiKey)
            statusMessage = "Key saved"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func validateKey() async {
        isValidating = true
        defer { isValidating = false }
        do {
            let service = OpenAIService()
            let valid = try await service.validateAPIKey()
            statusMessage = valid ? "Key is valid ✓" : "Validation failed"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func deleteKey() {
        do {
            try KeychainService.deleteAPIKey()
            apiKey = ""
            statusMessage = "Key deleted"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}
