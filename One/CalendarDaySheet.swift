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

    @State private var dragOffset: CGFloat = 0

    /// Keeps list content scrollable above the floating tab bar while the sheet surface extends to the screen bottom.
    private let tabBarContentInset = BottomSheetMetrics.tabBarContentInset

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let midHeight = SheetDetent.mid.height(in: totalHeight)
            let sheetBottom = geo.frame(in: .named(expandedTopCoordinateSpace)).maxY
            let expandedHeight = expandedTop.map { sheetBottom - $0 }
            let fullHeight = max(expandedHeight ?? SheetDetent.full.height(in: totalHeight), midHeight)
            let baseHeight = detent == .full ? fullHeight : midHeight
            let currentHeight = Self.rubberBanded(baseHeight - dragOffset, min: midHeight, max: fullHeight)
            // coverExtraHeight can be negative to drop the sheet below mid (reveal FoldersBar).
            let sheetHeight = min(max(currentHeight + coverExtraHeight, midHeight * 0.45), totalHeight)

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
                    .simultaneousGesture(sheetDragGesture(baseHeight: baseHeight, midHeight: midHeight, fullHeight: fullHeight))

                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: sheetHeight)
                .frame(maxWidth: .infinity)
                .background(Color.sheetSurface)
                .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.gray.opacity(0.45))
            .frame(width: 36, height: 5)
    }

    private func sheetDragGesture(baseHeight: CGFloat, midHeight: CGFloat, fullHeight: CGFloat) -> some Gesture {
        // Global space: the sheet resizes under the finger, so local translation would feed back and jitter.
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                let velocity = value.velocity.height
                let projected = baseHeight - value.translation.height - velocity * 0.15
                let target: SheetDetent
                if velocity > 350 {
                    target = .mid
                } else if velocity < -350 {
                    target = .full
                } else {
                    target = projected > (midHeight + fullHeight) / 2 ? .full : .mid
                }

                if target != detent {
                    Haptics.selection()
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    detent = target
                    dragOffset = 0
                }
            }
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
