//
//  AppSettings.swift
//  The Vault
//
//  User preferences that aren't part of the media index: the Claude API key
//  (stored in Keychain, only its presence exposed here) and analysis options.
//

import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    /// Keychain account under which the Claude key is stored.
    static let claudeAccount = "anthropic"

    /// Whether a Claude API key is currently stored. Drives the Stage-B UI.
    @Published private(set) var hasClaudeKey: Bool

    /// Run the free on-device analysis pass automatically as media is imported.
    @Published var autoAnalyzeOnImport: Bool {
        didSet { defaults.set(autoAnalyzeOnImport, forKey: Keys.autoAnalyze) }
    }

    /// Use precise (slower) optical-flow motion instead of the fast frame-diff.
    @Published var highPrecisionMotion: Bool {
        didSet { defaults.set(highPrecisionMotion, forKey: Keys.highPrecisionMotion) }
    }

    /// Spend Claude credits automatically after import (off by default so the
    /// user controls when credits are used — Phase 5).
    @Published var autoEnhanceWithAI: Bool {
        didSet { defaults.set(autoEnhanceWithAI, forKey: Keys.autoEnhance) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let autoAnalyze = "autoAnalyzeOnImport"
        static let highPrecisionMotion = "highPrecisionMotion"
        static let autoEnhance = "autoEnhanceWithAI"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoAnalyzeOnImport = defaults.object(forKey: Keys.autoAnalyze) as? Bool ?? false
        self.highPrecisionMotion = defaults.bool(forKey: Keys.highPrecisionMotion)
        self.autoEnhanceWithAI = defaults.bool(forKey: Keys.autoEnhance)
        self.hasClaudeKey = KeychainStore.get(account: Self.claudeAccount) != nil
    }

    // MARK: - API key

    func saveClaudeKey(_ key: String) {
        KeychainStore.set(key, account: Self.claudeAccount)
        hasClaudeKey = KeychainStore.get(account: Self.claudeAccount) != nil
    }

    func clearClaudeKey() {
        KeychainStore.delete(account: Self.claudeAccount)
        hasClaudeKey = false
    }

    /// Read the key when actually making an API call (Phase 5). Not published.
    func claudeKey() -> String? { KeychainStore.get(account: Self.claudeAccount) }
}
