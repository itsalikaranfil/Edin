//
//  SwipeDeleteButton.swift
//  One
//

import SwiftUI

/// Trailing swipe "Delete" action shared by every list so all rows show the same red trash pill.
/// Pass `isDestructive: false` when the delete needs a confirmation first: the destructive role
/// removes the row right away.
struct SwipeDeleteButton: View {
    var isDestructive = true
    let action: () -> Void

    var body: some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            Label("Delete", systemImage: "trash")
                .labelStyle(.titleAndIcon)
        }
        .tint(Color(uiColor: .systemRed))
    }
}
