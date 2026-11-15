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
    /// Pills inside a draggable area (e.g. the calendar sheet header) set this to false. Glass is
    /// rendered on its own layer that can lag or animate separately while the sheet moves, so those
    /// pills draw a plain capsule that matches the glass look on the solid sheet surface instead.
    @Entry var glassPillsInteractive: Bool = true
}

private struct GlassCapsulePillModifier: ViewModifier {
    let active: Bool
    @Environment(\.glassPillsInteractive) private var interactive
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if interactive {
            let base: Glass = active ? .regular.tint(.white.opacity(0.15)) : .regular
            content.glassEffect(base.interactive(), in: .capsule)
        } else {
            content.background(staticCapsule)
        }
    }

    private var staticCapsule: some View {
        let isDark = colorScheme == .dark
        let fill: Color = isDark
            ? .white.opacity(active ? 0.22 : 0.12)
            : (active ? Color.black.opacity(0.08) : .white)
        let stroke: Color = isDark ? .white.opacity(0.10) : .black.opacity(0.08)
        return Capsule()
            .fill(fill)
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 0.5))
    }
}
