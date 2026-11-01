//
//  AttachmentPreviewSheet.swift
//  One
//

import QuickLook
import SwiftUI
import UIKit

/// QuickLook preview for attachments. SwiftUI's `quickLookPreview` modifier is macOS-only,
/// so `QLPreviewController` is wrapped here. Wrapping it in a navigation controller gives
/// the system Done and Share buttons, and passing every URL lets you swipe between files.
struct AttachmentPreviewSheet: UIViewControllerRepresentable {
    let urls: [URL]
    var startIndex: Int = 0
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.delegate = context.coordinator
        if urls.indices.contains(startIndex) {
            preview.currentPreviewItemIndex = startIndex
        }
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.urls = urls
        context.coordinator.onDismiss = onDismiss
        guard let preview = controller.viewControllers.first as? QLPreviewController else { return }
        preview.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var urls: [URL]
        var onDismiss: () -> Void

        init(urls: [URL], onDismiss: @escaping () -> Void) {
            self.urls = urls
            self.onDismiss = onDismiss
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            urls.count
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            urls[index] as NSURL
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            onDismiss()
        }
    }
}

/// What the detail sheet hands to the previewer: materialized file URLs plus where to start.
struct AttachmentPreviewRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
    let startIndex: Int
}
