//
//  AppDelegate.swift
//  The Vault
//
//  Minimal AppKit delegate for app-lifecycle hooks not covered by SwiftUI:
//  appearance enforcement and accepting files dragged onto the Dock icon.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dark-mode-first regardless of system setting.
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Folders dropped on the Dock icon are added as sources.
    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .vaultOpenURLs, object: urls)
    }
}

extension Notification.Name {
    static let vaultOpenURLs = Notification.Name("com.thevault.openURLs")
}
