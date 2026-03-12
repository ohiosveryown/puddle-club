//
//  ContentView.swift
//  puddle-club
//
//  Created by Matthew Pence on 3/3/26.
//

import SwiftUI

@Observable
class SearchBarVisibility {
    var isHidden = false
}

struct ContentView: View {
    @State private var searchText = ""
    @State private var isSearchFocused = false
    @State private var showAPIKeyPrompt = false
    @State private var searchBarVisibility = SearchBarVisibility()

    var body: some View {
        HomeView(searchText: $searchText)
            .environment(searchBarVisibility)
            .safeAreaInset(edge: .bottom) {
                FloatingSearchBar(text: $searchText, isFocused: $isSearchFocused)
                    .padding(.horizontal, 16)
                    .padding(.bottom, isSearchFocused ? 12 : -12)
                    .opacity(searchBarVisibility.isHidden ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: searchBarVisibility.isHidden)
            }
            .onAppear {
                if (try? KeychainService.loadAPIKey()) == nil {
                    showAPIKeyPrompt = true
                }
            }
            .sheet(isPresented: $showAPIKeyPrompt) {
                APIKeySetupView()
            }
    }
}

// MARK: - First-launch API key setup

private struct APIKeySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect OpenAI")
                        .font(.largeTitle.bold())
                    Text("Puddle Club uses OpenAI to analyse your screenshots. Enter your API key to get started.")
                        .foregroundStyle(.secondary)
                }

                SecureField("sk-…", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    saveAndDismiss()
                } label: {
                    Text("Save & Continue")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func saveAndDismiss() {
        do {
            try KeychainService.saveAPIKey(apiKey.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            self.error = "Couldn't save key: \(error.localizedDescription)"
        }
    }
}

