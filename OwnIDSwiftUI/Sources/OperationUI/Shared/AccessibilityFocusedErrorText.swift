import SwiftUI

@available(iOS 15.0, *)
internal struct AccessibilityFocusedErrorText: View {
    internal let message: String
    internal let color: Color
    internal let alignment: TextAlignment
    internal let focusTrigger: Int

    @AccessibilityFocusState private var isFocused: Bool

    internal var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(color)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityFocused($isFocused)
            .onAppear(perform: requestFocus)
            .onChangeCompat(of: focusTrigger) { _ in requestFocus() }
    }

    @MainActor
    private func requestFocus() {
        isFocused = false
        DispatchQueue.main.async {
            isFocused = true
        }
    }
}
