//
//  NewFolderView.swift
//  One
//

import SwiftUI
import CoreData

struct NewFolderView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    var folderToEdit: Folder? = nil
    var onSaved: () -> Void

    @State private var folderName = ""
    @FocusState private var isNameFieldFocused: Bool

    private var isEditing: Bool {
        folderToEdit != nil
    }

    private var trimmedName: String {
        folderName.trimmingCharacters(in: .whitespaces)
    }

    private var isReservedName: Bool {
        FolderStore.isReservedInboxName(trimmedName)
    }

    private var isUnchangedName: Bool {
        guard let folderToEdit else { return false }
        return trimmedName == (folderToEdit.name ?? "").trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isReservedName && (!isEditing || !isUnchangedName)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Folder name", text: $folderName)
                    .font(.body)
                    .foregroundColor(Color.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(saveFolder)

                Spacer(minLength: 0)
            }
            .background(Color.sheetSurface)
            .navigationTitle(isEditing ? "Rename Folder" : "New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassCancelButton {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarGlassConfirmButton(isEnabled: canSave, action: saveFolder)
                }
            }
            .onAppear {
                if let folderToEdit {
                    folderName = folderToEdit.name ?? ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isNameFieldFocused = true
                }
            }
        }
    }

    private func saveFolder() {
        let name = trimmedName
        guard canSave else { return }

        if let folderToEdit {
            FolderStore.rename(folderToEdit, to: name, context: viewContext)
        } else {
            let folder = Folder(context: viewContext)
            folder.id = UUID()
            folder.name = name
            folder.sortOrder = nextSortOrder()
            PersistenceController.shared.save()
        }

        onSaved()
        dismiss()
    }

    private func nextSortOrder() -> Int16 {
        guard NSEntityDescription.entity(forEntityName: "Folder", in: viewContext) != nil else {
            return 0
        }
        let request = NSFetchRequest<Folder>(entityName: "Folder")
        let existing = (try? viewContext.fetch(request)) ?? []
        return Int16((existing.map { Int($0.sortOrder) }.max() ?? 0) + 1)
    }
}
