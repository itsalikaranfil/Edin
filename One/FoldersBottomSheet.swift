//
//  FoldersBottomSheet.swift
//  One
//

import SwiftUI

struct FoldersBottomSheet<Content: View>: View {
    @Binding var detent: SheetDetent
    @Binding var isPresented: Bool
    /// Parent container height so the sheet can size to the panel only (not full-screen),
    /// which keeps title + list moving together under `.move(edge: .bottom)`.
    var containerHeight: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let baseHeight = height(for: detent, in: containerHeight)
        let midHeight = height(for: .mid, in: containerHeight)
        let fullHeight = height(for: .full, in: containerHeight)
        let minHeight = midHeight * 0.6
        let currentHeight = min(max(baseHeight - dragOffset, minHeight), fullHeight)

        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(sheetDragGesture(baseHeight: baseHeight, midHeight: midHeight, fullHeight: fullHeight))

            content()
        }
        .frame(height: currentHeight)
        .frame(maxWidth: .infinity)
        .background(Color.sheetSurface)
        .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func height(for detent: SheetDetent, in totalHeight: CGFloat) -> CGFloat {
        switch detent {
        case .mid: return totalHeight * 0.55
        case .full: return totalHeight * 0.90
        }
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.gray.opacity(0.45))
            .frame(width: 36, height: 5)
    }

    private func sheetDragGesture(baseHeight: CGFloat, midHeight: CGFloat, fullHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let projected = baseHeight - value.translation.height - value.predictedEndTranslation.height * 0.35
                let velocity = value.predictedEndTranslation.height

                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if velocity > 60 || projected < midHeight * 0.75 {
                        isPresented = false
                    } else if velocity > 40 {
                        detent = .mid
                    } else if velocity < -40 {
                        detent = .full
                    } else if projected > (midHeight + fullHeight) / 2 {
                        detent = .full
                    } else {
                        detent = .mid
                    }
                    dragOffset = 0
                }
            }
    }
}
