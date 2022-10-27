import SwiftUI
import OwnIDCoreSDK
import DemoComponents

extension BlueButton {
    init(text: String, action: @escaping () -> Void, coloring: Color = OwnID.Colors.blue) {
        self.init(text: text, action: action, color: coloring)
    }
}
