import SwiftUI

// MARK: - Liquid Glass Modifiers (macOS 26+, fallback gracieux sur 14–25)
//
// Règle de l'art Apple : ne jamais simuler le Liquid Glass sur les OS antérieurs.
// On utilise `.background(.ultraThinMaterial)` comme fallback recommandé par la HIG.
// Les call sites sont identiques quel que soit l'OS — zéro #available dans les views.

extension View {

    /// Card semi-transparente : Liquid Glass sur macOS 26+, material sombre sur 14–25.
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Fond de panneau principal (sidebar, detail) : plus opaque que glassCard.
    func glassPanelBackground() -> some View {
        modifier(GlassPanelModifier())
    }

    /// Highlight de sélection sur une row / node.
    func glassSelectionHighlight(isSelected: Bool) -> some View {
        modifier(GlassSelectionModifier(isSelected: isSelected))
    }
}

// MARK: - Implementations

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

private struct GlassPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular.interactive(true), in: Rectangle())
        } else {
            content
                .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        }
    }
}

private struct GlassSelectionModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(
                    isSelected ? .regular : Glass.regular.interactive(false),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .opacity(isSelected ? 1 : 0)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(isSelected ? 0.08 : 0))
                )
        }
    }
}
