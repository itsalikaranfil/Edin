//
//  GlassPillStyle.swift
//  One
//

import SwiftUI

extension View {
    /// Capsule liquid glass for tappable header/filter pills.
    func glassCapsulePill(active: Bool = false) -> some View {
        modifier(GlassCapsulePillModifier(active: active))
    }

    /// Circle liquid glass for sheet close (X) buttons.
    func glassCircleClose() -> some View {
        glassEffect(.regular.interactive(), in: .circle)
    }

    /// Rounded rect liquid glass for floating menus (e.g. plus type picker).
    func glassRoundedCard(cornerRadius: CGFloat = 14) -> some View {
        glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
    }

    /// Widget circle glass. `glassEffect` does not render in WidgetKit, so this
    /// uses material + highlight to keep the plus visible.
    func widgetGlassCircle() -> some View {
        background {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                }
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
    }
}

extension EnvironmentValues {
    /// Interactive glass stretches toward the finger, so pills inside a draggable area
    /// (e.g. the calendar sheet header) turn it off to stay put while the sheet is dragged.
    @Entry var glassPillsInteractive: Bool = true
}

private struct GlassCapsulePillModifier: ViewModifier {
    let active: Bool
    @Environment(\.glassPillsInteractive) private var interactive

    func body(content: Content) -> some View {
        let base: Glass = active ? .regular.tint(.white.opacity(0.15)) : .regular
        content.glassEffect(base.interactive(interactive), in: .capsule)
    }
}
