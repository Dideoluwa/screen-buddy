//
//  SettingsView.swift
//  screen buddy
//
//  Settings interface for API key configuration
//

import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var showKey: Bool = false
    @State private var isSaved: Bool = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gemini API Key")
                        .font(.headline)
                    
                    Text("Get your API key from [Google AI Studio](https://aistudio.google.com/apikey)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        if showKey {
                            TextField("Enter API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    HStack {
                        Button("Save") {
                            saveAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty)
                        
                        if isSaved {
                            Text("✓ Saved")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        if GeminiService.shared.isConfigured {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("AI Configuration")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable random movement", isOn: .constant(true))
                        .disabled(true)
                    
                    Text("Robot will occasionally move around the screen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Behavior")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Buddy")
                        .font(.headline)
                    Text("Your AI desktop companion")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Version 1.0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 350)
        .onAppear {
            loadAPIKey()
        }
    }
    
    private func loadAPIKey() {
        if let savedKey = UserDefaults.standard.string(forKey: "gemini_api_key") {
            apiKey = savedKey
        }
    }
    
    private func saveAPIKey() {
        GeminiService.shared.configure(apiKey: apiKey)
        isSaved = true
        
        // Reset saved indicator after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isSaved = false
        }
    }
}

#Preview {
    SettingsView()
}
