import SwiftUI

struct PresentationDetents: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.medium, .large])
        } else {
            content
        }
    }
}
