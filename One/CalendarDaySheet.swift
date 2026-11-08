//
//  CalendarDaySheet.swift
//  One
//

import SwiftUI
import UIKit

enum SheetDetent: CaseIterable {
    case mid
    case full

    func height(in totalHeight: CGFloat) -> CGFloat {
        switch self {
        case .mid:
            let screenHeight = UIScreen.main.bounds.height
            let fraction: CGFloat = screenHeight >= 932 ? 0.50 : 0.45
            return totalHeight * fraction
        case .full: return totalHeight * 0.90
        }
    }
}

enum BottomSheetMetrics {
    static let tabBarContentInset: CGFloat = 74
}

struct CalendarDaySheet<Header: View, Content: View>: View {
    @Binding var detent: SheetDetent
    /// Height delta vs the current detent. Positive covers content above (FoldersBar);
    /// negative shortens the sheet so that content is revealed.
    var coverExtraHeight: CGFloat = 0
    /// Overrides the `.full` detent so the sheet's top edge sits at this Y in
    /// `expandedTopCoordinateSpace` (never shorter than `.mid`).
    var expandedTop: CGFloat? = nil
    var expandedTopCoordinateSpace: String = ""
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    @State private var drag = SheetDragState()
    @GestureState private var isGestureActive = false

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let midHeight = SheetDetent.mid.height(in: totalHeight)
            let sheetBottom = geo.frame(in: .named(expandedTopCoordinateSpace)).maxY
            let expandedHeight = expandedTop.map { sheetBottom - $0 }
            let fullHeight = max(expandedHeight ?? SheetDetent.full.height(in: totalHeight), midHeight)
            let metrics = SheetDragMetrics(
                baseHeight: detent == .full ? fullHeight : midHeight,
                midHeight: midHeight,
                fullHeight: fullHeight,
                coverExtraHeight: coverExtraHeight,
                totalHeight: totalHeight
            )
            let shape = UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        dragHandle
                            .padding(.top, 10)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity)

                        header()
                    }
                    .contentShape(Rectangle())
                    // Simultaneous so the filter pills in the header stay tappable.
                    .simultaneousGesture(sheetDragGesture(metrics: metrics))

                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // While dragging, the surface is laid out once at full container height and only
                // offset per frame; resizing it every frame re-lays out the list and stutters.
                .frame(height: drag.isInteracting ? totalHeight : metrics.sheetHeight(dragOffset: 0))
                .frame(maxWidth: .infinity)
                .clipShape(shape)
                .glassEffect(.regular.tint(Color.calendarSheetGlassTint), in: shape)
                .modifier(SheetDragOffset(drag: drag, metrics: metrics))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: isGestureActive) { _, active in
            // A drag cancelled by the system never reaches onEnded.
            if !active, drag.isDragging {
                settle(to: detent)
            }
        }
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.gray.opacity(0.45))
            .frame(width: 36, height: 5)
    }

    private func sheetDragGesture(metrics: SheetDragMetrics) -> some Gesture {
        // Global space: the sheet moves under the finger, so local translation would feed back and jitter.
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($isGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if !drag.isDragging {
                        drag.isDragging = true
                        drag.isInteracting = true
                        drag.settleID += 1
                    }
                    drag.offset = value.translation.height
                }
            }
            .onEnded { value in
                let velocity = value.velocity.height
                let projected = metrics.baseHeight - value.translation.height - velocity * 0.2
                let target: SheetDetent
                if abs(velocity) > 250 {
                    target = velocity < 0 ? .full : .mid
                } else {
                    target = abs(projected - metrics.fullHeight) < abs(projected - metrics.midHeight) ? .full : .mid
                }

                if target != detent {
                    Haptics.selection()
                }
                settle(to: target)
            }
    }

    private func settle(to target: SheetDetent) {
        drag.isDragging = false
        let settleID = drag.settleID
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            detent = target
            drag.offset = 0
        } completion: {
            guard drag.settleID == settleID, !drag.isDragging else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                drag.isInteracting = false
            }
        }
    }
}

@Observable
private final class SheetDragState {
    var offset: CGFloat = 0
    var isDragging = false
    /// True from drag start until the settle animation finishes.
    var isInteracting = false
    var settleID = 0
}

private struct SheetDragMetrics {
    let baseHeight: CGFloat
    let midHeight: CGFloat
    let fullHeight: CGFloat
    let coverExtraHeight: CGFloat
    let totalHeight: CGFloat

    func sheetHeight(dragOffset: CGFloat) -> CGFloat {
        let height = Self.rubberBanded(baseHeight - dragOffset, min: midHeight, max: fullHeight)
        // coverExtraHeight can be negative to drop the sheet below mid (reveal FoldersBar).
        return min(max(height + coverExtraHeight, midHeight * 0.45), totalHeight)
    }

    /// Lets the sheet stretch a little past its detents with resistance instead of stopping dead.
    private static func rubberBanded(_ height: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        let limit: CGFloat = 50
        func resist(_ overshoot: CGFloat) -> CGFloat {
            limit * (1 - 1 / (overshoot / limit * 0.55 + 1))
        }
        if height > upper { return upper + resist(height - upper) }
        if height < lower { return lower - resist(lower - height) }
        return height
    }
}

/// Reads the drag offset here rather than in the sheet body, so per-frame drag updates
/// don't re-evaluate the sheet's header and list.
private struct SheetDragOffset: ViewModifier {
    let drag: SheetDragState
    let metrics: SheetDragMetrics

    func body(content: Content) -> some View {
        content.offset(y: drag.isInteracting ? metrics.totalHeight - metrics.sheetHeight(dragOffset: drag.offset) : 0)
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
