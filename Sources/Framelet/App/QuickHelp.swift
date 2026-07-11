import SwiftUI

private struct QuickHelpModifier: ViewModifier {
    let text: LocalizedStringKey
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isPresented = hovering
            }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                Text(text)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .presentationCompactAdaptation(.popover)
            }
    }
}

extension View {
    /// An immediate hover explanation for icon-heavy controls. Unlike AppKit's standard
    /// help tag, this does not wait for the system tooltip delay.
    func quickHelp(_ text: LocalizedStringKey) -> some View {
        modifier(QuickHelpModifier(text: text))
    }
}
