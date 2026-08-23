//
//  TheVaultApp.swift
//  The Vault
//
//  App entry point. Owns the LibraryStore and VolumeMonitor and wires the
//  main window scene. Dark-mode-first, single-window media browser.
//

import SwiftUI

@main
struct TheVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var store = LibraryStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var volumeMonitor = VolumeMonitor()

    var body: some Scene {
        Window("The Vault", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .frame(minWidth: 1040, minHeight: 680)
                .preferredColorScheme(.dark)
                .onAppear {
                    volumeMonitor.onChange = { store.refreshSourceAvailability() }
                    volumeMonitor.start()
                    syncAnalysisPreferences()
                }
                .onChange(of: settings.autoAnalyzeOnImport) { _ in syncAnalysisPreferences() }
                .onChange(of: settings.highPrecisionMotion) { _ in syncAnalysisPreferences() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { VaultCommands(store: store) }

        Settings {
            SettingsView().environmentObject(settings)
        }
    }

    /// Push the user's analysis preferences into the store so the auto-pass
    /// after import respects them.
    private func syncAnalysisPreferences() {
        store.autoAnalyzeOnImport = settings.autoAnalyzeOnImport
        store.highPrecisionMotion = settings.highPrecisionMotion
    }
}

/// Menu-bar commands (File ▸ Add Source…, view switching, selection utilities).
struct VaultCommands: Commands {
    @ObservedObject var store: LibraryStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Source…") { SourcePicker.present(into: store) }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandMenu("View") {
            ForEach(BrowserViewMode.allCases) { mode in
                Button(mode.rawValue) { store.viewMode = mode }
            }
            Divider()
            Button("Select All") { store.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
            Button("Deselect All") { store.clearSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        CommandMenu("Selection") {
            Button("Reveal in Finder") {
                NSWorkspace.shared.reveal(store.selectedURLs)
            }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Copy File Paths") {
                NSPasteboard.general.writeFileURLs(store.selectedURLs)
            }.keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }
}
