//
//  FoldersView.swift
//  One
//

import SwiftUI
import CoreData

private enum FolderNameSheetMode: Identifiable {
    case create
    case rename(Folder)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .rename(let folder):
            return folder.objectID.uriRepresentation().absoluteString
        }
    }

    var folderToEdit: Folder? {
        if case .rename(let folder) = self { return folder }
        return nil
    }
}

struct FoldersView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var coordinator = FolderSheetCoordinator.shared

    var onFolderSelected: (Folder) -> Void
    var onFolderDeleted: ((Folder) -> Void)?
    @Binding var isPresented: Bool

    var bottomContentInset: CGFloat = 0

    @State private var folders: [Folder] = []
    @State private var folderNameSheetMode: FolderNameSheetMode?

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                ForEach(folders, id: \.objectID) { folder in
                    FolderListRow(folder: folder) {
                        onFolderSelected(folder)
                        isPresented = false
                    }
                    .id(folder.name ?? "")
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.sheetSurface)
                    .contextMenu {
                        if !FolderStore.isInbox(folder) {
                            Button {
                                folderNameSheetMode = .rename(folder)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color.primary)

                            Button(role: .destructive) {
                                deleteFolder(folder)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !FolderStore.isInbox(folder) {
                            Button {
                                folderNameSheetMode = .rename(folder)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                deleteFolder(folder)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.bottom, bottomContentInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            FolderStore.ensureInboxExists(context: viewContext)
            reloadFolders()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
            reloadFolders()
        }
        .onChange(of: coordinator.requestAddFolder) { _, requested in
            guard requested else { return }
            folderNameSheetMode = .create
            coordinator.consumeAddFolderRequest()
        }
        .sheet(item: $folderNameSheetMode) { mode in
            NewFolderView(folderToEdit: mode.folderToEdit, onSaved: reloadFolders)
                .environment(\.managedObjectContext, viewContext)
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Folders")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.primaryText)

            Spacer()

            SheetClosePill {
                isPresented = false
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func reloadFolders() {
        viewContext.processPendingChanges()
        folders = FolderStore.fetchAll(context: viewContext)
    }

    private func deleteFolder(_ folder: Folder) {
        guard !FolderStore.isInbox(folder) else { return }
        onFolderDeleted?(folder)
        viewContext.delete(folder)
        PersistenceController.shared.save()
        reloadFolders()
    }
}

private struct FolderListRow: View {
    @ObservedObject var folder: Folder
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color.folderCyan)

                    Text(FolderStore.displayName(for: folder))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(Color.primaryText)

                    Spacer()
                }
                .padding(.vertical, 16)

                Divider()
                    .background(Color.gray.opacity(0.25))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
