//
//  AttachmentsSectionViews.swift
//  One
//

import CoreData
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editor

/// Attachments section for the create and edit forms. Operates on staged drafts so the
/// form's Cancel discards picked files, matching how the rest of those forms behave.
struct AttachmentsEditorSection: View {
    @Binding var drafts: [AttachmentDraft]
    var onError: (String) -> Void

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var isImporting = false

    var body: some View {
        Section("Attachments") {
            ForEach(drafts) { draft in
                AttachmentRowLabel(
                    id: draft.id,
                    filename: draft.filename,
                    typeIdentifier: draft.typeIdentifier,
                    byteCount: draft.byteCount,
                    inlineData: draft.data
                )
            }
            .onDelete { offsets in
                Haptics.light()
                drafts.remove(atOffsets: offsets)
            }

            addRow
        }
    }

    /// The pickers hang off this row rather than the enclosing `Section`, because presentation
    /// modifiers attached to a Section inside a Form do not reliably present.
    private var addRow: some View {
        Menu {
            Button {
                showPhotoPicker = true
            } label: {
                Label("Photos", systemImage: "photo.on.rectangle")
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Files", systemImage: "folder")
            }
        } label: {
            HStack(spacing: 12) {
                Label {
                    Text("Add Attachment")
                } icon: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                }
                .foregroundColor(Color.primaryText)

                Spacer()

                if isImporting {
                    ProgressView()
                }
            }
        }
        .disabled(isImporting)
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoSelection,
            maxSelectionCount: nil,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await importPhotos(items) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                onError(error.localizedDescription)
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false }

        for (index, item) in items.enumerated() {
            let typeIdentifier = item.supportedContentTypes.first?.identifier
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    onError(AttachmentImportError.unreadable(filename: String(localized: "Photo")).localizedDescription)
                    continue
                }
                let filename = AttachmentStore.generatedFilename(
                    for: typeIdentifier,
                    index: drafts.count + index + 1
                )
                guard data.count <= AttachmentStore.maxByteCount else {
                    onError(AttachmentImportError.tooLarge(filename: filename).localizedDescription)
                    continue
                }
                append(filename: filename, typeIdentifier: typeIdentifier, data: data)
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            let filename = url.lastPathComponent
            let needsScope = url.startAccessingSecurityScopedResource()
            defer {
                if needsScope { url.stopAccessingSecurityScopedResource() }
            }

            guard let data = try? Data(contentsOf: url) else {
                onError(AttachmentImportError.unreadable(filename: filename).localizedDescription)
                continue
            }
            guard data.count <= AttachmentStore.maxByteCount else {
                onError(AttachmentImportError.tooLarge(filename: filename).localizedDescription)
                continue
            }
            let typeIdentifier = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
                ?? UTType(filenameExtension: url.pathExtension)?.identifier
            append(filename: filename, typeIdentifier: typeIdentifier, data: data)
        }
    }

    private func append(filename: String, typeIdentifier: String?, data: Data) {
        drafts.append(
            AttachmentDraft(
                id: UUID(),
                filename: filename,
                typeIdentifier: typeIdentifier,
                byteCount: data.count,
                existingObjectID: nil,
                data: data
            )
        )
    }
}

// MARK: - Read-only viewer

/// Attachments list for the read-only detail sheet. Tapping a row opens QuickLook.
struct AttachmentsInfoSection: View {
    let attachments: [AttachmentRef]
    var onSelect: (Int) -> Void

    var body: some View {
        Section("Attachments") {
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, ref in
                Button {
                    Haptics.light()
                    onSelect(index)
                } label: {
                    HStack(spacing: 12) {
                        AttachmentRowLabel(
                            id: ref.id,
                            filename: ref.filename,
                            typeIdentifier: ref.typeIdentifier,
                            byteCount: ref.byteCount,
                            inlineData: nil,
                            objectID: ref.objectID
                        )

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Shared row

/// Thumbnail plus filename and size. Image bytes are loaded lazily and cached, so a long
/// list of attachments does not decode everything up front.
private struct AttachmentRowLabel: View {
    let id: UUID
    let filename: String
    let typeIdentifier: String?
    let byteCount: Int
    let inlineData: Data?
    var objectID: NSManagedObjectID?

    @Environment(\.managedObjectContext) private var viewContext
    @State private var thumbnail: UIImage?

    private let side: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .foregroundColor(Color.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if byteCount > 0 {
                    Text(AttachmentStore.sizeText(byteCount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .task(id: id) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: AttachmentStore.symbolName(for: typeIdentifier))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.eventBlue)
                .frame(width: side, height: side)
                .background(Color.pillBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func loadThumbnail() async {
        if let cached = AttachmentThumbnailCache.shared.image(for: id) {
            thumbnail = cached
            return
        }
        guard AttachmentStore.isImage(typeIdentifier) else { return }

        let data: Data?
        if let inlineData {
            data = inlineData
        } else if let objectID {
            let ref = AttachmentRef(
                id: id,
                objectID: objectID,
                filename: filename,
                typeIdentifier: typeIdentifier,
                byteCount: byteCount
            )
            data = AttachmentStore.data(for: ref, context: viewContext)
        } else {
            data = nil
        }

        guard let data else { return }
        let side = self.side
        let image = await Task.detached(priority: .userInitiated) {
            AttachmentStore.downsampledImage(from: data, maxPixelSize: side * 3)
        }.value

        guard let image else { return }
        AttachmentThumbnailCache.shared.store(image, for: id)
        thumbnail = image
    }
}
