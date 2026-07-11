import SwiftUI

extension View {
    func quickHelp(_ text: LocalizedStringKey) -> some View {
        help(Text(text))
    }
}
