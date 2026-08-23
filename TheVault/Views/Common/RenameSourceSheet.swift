//
//  RenameSourceSheet.swift
//  The Vault
//
//  Small shared sheet to give a source a nickname. Used from the sidebar and
//  from a project's source manager.
//

import SwiftUI

struct RenameSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: Source
    @Binding var text: String
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Source").font(.headline).foregroundStyle(Theme.textPrimary)
            Text(source.path).font(.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
            TextField("Nickname", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 360).background(Theme.surface)
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}
