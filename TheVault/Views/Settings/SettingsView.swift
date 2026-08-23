//
//  SettingsView.swift
//  The Vault
//
//  Preferences window (⌘,): Claude API key entry + analysis options.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var keyDraft: String = ""

    var body: some View {
        TabView {
            analysisTab
                .tabItem { Label("Analysis", systemImage: "wand.and.stars") }
            apiTab
                .tabItem { Label("Claude API", systemImage: "key") }
        }
        .frame(width: 460, height: 300)
        .background(Theme.background)
    }

    // MARK: Analysis

    private var analysisTab: some View {
        Form {
            Toggle("Analyze footage on import", isOn: $settings.autoAnalyzeOnImport)
            Text("Runs the free, on-device pass (mistake & quality flags, content tags) as media is indexed. No credits are used.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            Divider()

            Toggle("High-precision motion analysis", isOn: $settings.highPrecisionMotion)
            Text("Uses optical flow instead of the fast frame-difference estimate. More accurate shake/motion detection, but slower on large libraries.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(20)
    }

    // MARK: Claude API

    private var apiTab: some View {
        Form {
            HStack(spacing: 6) {
                Circle()
                    .fill(settings.hasClaudeKey ? Theme.online : Theme.offline)
                    .frame(width: 9, height: 9)
                Text(settings.hasClaudeKey ? "API key stored in Keychain" : "No API key stored")
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.callout)

            SecureField("sk-ant-…", text: $keyDraft)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save Key") {
                    settings.saveClaudeKey(keyDraft)
                    keyDraft = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                if settings.hasClaudeKey {
                    Button("Remove", role: .destructive) { settings.clearClaudeKey() }
                }
                Spacer()
            }

            Divider()

            Toggle("Enhance new imports with AI automatically", isOn: $settings.autoEnhanceWithAI)
                .disabled(!settings.hasClaudeKey)
            Text("When off (recommended), AI content tagging runs only when you choose 'Enhance with AI' on a project — so you control when Claude credits are spent.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(20)
    }
}
