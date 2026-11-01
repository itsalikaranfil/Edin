//
//  ChecklistSectionViews.swift
//  One
//

import SwiftUI

// MARK: - Editor

/// Notes-style checklist for the create and edit forms. Return inserts a new row
/// below the current one; submitting an empty row ends the list.
struct ChecklistEditorSection: View {
    @Binding var drafts: [ChecklistDraft]
    @FocusState private var focusedID: UUID?

    var body: some View {
        Section {
            ForEach($drafts) { $draft in
                ChecklistEditorRow(draft: $draft, focusedID: $focusedID) {
                    submit(id: draft.id)
                }
            }
            .onDelete { offsets in
                Haptics.light()
                drafts.remove(atOffsets: offsets)
            }
            .onMove { source, destination in
                drafts.move(fromOffsets: source, toOffset: destination)
            }

            Button {
                Haptics.light()
                addItem()
            } label: {
                Label {
                    Text("Add Item")
                } icon: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                }
                .foregroundColor(Color.primaryText)
            }
        } header: {
            HStack {
                Text("Checklist")
                Spacer()
                if !drafts.isEmpty {
                    EditButton()
                        .font(.footnote)
                        .textCase(nil)
                }
            }
        }
    }

    private func submit(id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        if drafts[index].isBlank {
            drafts.remove(at: index)
            focusedID = nil
            return
        }
        let next = ChecklistDraft.empty()
        drafts.insert(next, at: index + 1)
        focusedID = next.id
    }

    private func addItem() {
        let next = ChecklistDraft.empty()
        drafts.append(next)
        focusedID = next.id
    }
}

private struct ChecklistEditorRow: View {
    @Binding var draft: ChecklistDraft
    var focusedID: FocusState<UUID?>.Binding
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.selection()
                draft.isCompleted.toggle()
            } label: {
                Image(systemName: draft.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(draft.isCompleted ? Color.eventBlue : Color.primaryText.opacity(0.35))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            TextField("Item", text: $draft.title)
                .foregroundColor(draft.isCompleted ? Color.primaryText.opacity(0.45) : Color.primaryText)
                .strikethrough(draft.isCompleted, color: Color.primaryText.opacity(0.35))
                .focused(focusedID, equals: draft.id)
                .submitLabel(.next)
                .onSubmit(onSubmit)
        }
    }
}

// MARK: - Read-only viewer

/// Checklist on the detail sheet. Tapping a circle toggles and saves immediately.
struct ChecklistInfoSection: View {
    let items: [ChecklistRef]
    var onToggle: (ChecklistRef) -> Void

    private var completedCount: Int {
        items.filter(\.isCompleted).count
    }

    var body: some View {
        Section {
            ForEach(items) { item in
                Button {
                    Haptics.selection()
                    onToggle(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(item.isCompleted ? Color.eventBlue : Color.primaryText.opacity(0.35))
                            .frame(width: 28, height: 28)

                        Text(item.title)
                            .foregroundColor(item.isCompleted ? Color.primaryText.opacity(0.45) : Color.primaryText)
                            .strikethrough(item.isCompleted, color: Color.primaryText.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("\(completedCount) of \(items.count)")
        }
    }
}
