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
            let currentHeight = min(max(baseHeight - dragOffset, midHeight), fullHeight)
            // coverExtraHeight can be negative to drop the sheet below mid (reveal FoldersBar).
            let sheetHeight = min(max(currentHeight + coverExtraHeight, midHeight * 0.45), totalHeight)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    dragHandle
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(sheetDragGesture(baseHeight: baseHeight, midHeight: midHeight, fullHeight: fullHeight))

                    header()

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
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let projected = baseHeight - value.translation.height - value.predictedEndTranslation.height * 0.35
                let velocity = value.predictedEndTranslation.height

                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if velocity > 40 {
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
