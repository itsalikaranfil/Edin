//
//  FoldersBar.swift
//  One
//

import SwiftUI

struct FoldersBarFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct FoldersBar: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color.folderCyan)

                Text("Folders")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(Color.primaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
