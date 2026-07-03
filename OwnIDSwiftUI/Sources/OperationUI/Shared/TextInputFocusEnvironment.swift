import SwiftUI

private struct OwnIDSuppressTextInputFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    internal var ownIDSuppressTextInputFocus: Bool {
        get { self[OwnIDSuppressTextInputFocusKey.self] }
        set { self[OwnIDSuppressTextInputFocusKey.self] = newValue }
    }
}
