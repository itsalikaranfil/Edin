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

    @State private var drag = SheetDragState()
    @GestureState private var isGestureActive = false

    var body: some View {
        let baseHeight = height(for: detent, in: containerHeight)
        let midHeight = height(for: .mid, in: containerHeight)
        let fullHeight = height(for: .full, in: containerHeight)

        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 10)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(sheetDragGesture(baseHeight: baseHeight, midHeight: midHeight, fullHeight: fullHeight))

            content()
        }
        .frame(height: drag.isInteracting ? containerHeight : baseHeight)
        .frame(maxWidth: .infinity)
        .calendarSheetBackground()
        .modifier(SheetDragOffset(drag: drag, containerHeight: containerHeight) { dragOffset in
            // Rubber-band only at the top; below mid the sheet follows the finger toward dismissal.
            min(SheetDragState.rubberBanded(baseHeight - dragOffset, min: 0, max: fullHeight), containerHeight)
        })
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: isGestureActive) { _, active in
            // A drag cancelled by the system never reaches onEnded.
            if !active, drag.isDragging {
                drag.settle {}
            }
        }
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
        // Global space: the sheet moves under the finger, so local translation would feed back and jitter.
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($isGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                drag.track(value.translation.height)
            }
            .onEnded { value in
                let velocity = value.velocity.height
                let projected = baseHeight - value.translation.height - velocity * 0.2

                if projected < midHeight * 0.75 || (velocity > 250 && detent == .mid) {
                    // The sheet is removed with its own move transition from where the finger left it.
                    drag.release()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        isPresented = false
                    }
                    return
                }

                let target: SheetDetent
                if abs(velocity) > 250 {
                    target = velocity < 0 ? .full : .mid
                } else {
                    target = abs(projected - fullHeight) < abs(projected - midHeight) ? .full : .mid
                }
                if target != detent {
                    Haptics.selection()
                }
                drag.settle {
                    detent = target
                }
            }
    }
}
