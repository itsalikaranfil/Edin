//
//  EmptyListSkeletonView.swift
//  One
//

import SwiftUI

struct EmptyListSkeletonView: View {
    var accessibilityLabel: String? = nil
    var surface: Color = .sheetSurface
    var icons: [String] = ["calendar", "circle"]

    private let barColor = Color.primaryText.opacity(0.18)
    private let iconColor = Color.primaryText.opacity(0.28)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                if index > 0 {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(height: 0.5)
                        .padding(.leading, 50)
                        .padding(.trailing, 16)
                }
                skeletonRow(systemImage: icon)
            }
        }
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .modifier(EmptyListSkeletonAccessibility(label: accessibilityLabel))
    }

    private func skeletonRow(systemImage: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(iconColor)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(barColor)
                    .frame(height: 11)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 72)
                Capsule()
                    .fill(barColor)
                    .frame(width: 96, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct EmptyListSkeletonAccessibility: ViewModifier {
    var label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
