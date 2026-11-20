//
//  TabBarVisibility.swift
//  One
//

import SwiftUI
import Combine

/// Tracks pushed pages that hide the tab bar, so the plus menu anchor over it can stop taking taps.
@MainActor
final class TabBarVisibility: ObservableObject {
    static let shared = TabBarVisibility()

    @Published private(set) var hidingPageCount = 0

    var isHidden: Bool { hidingPageCount > 0 }

    fileprivate func pageAppeared() {
        hidingPageCount += 1
    }

    fileprivate func pageDisappeared() {
        hidingPageCount = max(0, hidingPageCount - 1)
    }
}

private struct HidesTabBarModifier: ViewModifier {
    @State private var isCounted = false

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                guard !isCounted else { return }
                isCounted = true
                TabBarVisibility.shared.pageAppeared()
            }
            .onDisappear {
                guard isCounted else { return }
                isCounted = false
                TabBarVisibility.shared.pageDisappeared()
            }
    }
}

extension View {
    /// Hides the tab bar (and the plus control over it) while this page is shown.
    func hidesTabBar() -> some View {
        modifier(HidesTabBarModifier())
    }
}
