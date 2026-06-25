import UIKit

@MainActor
internal final class TextFieldFocusCoordinator {
    private static let focusRetryDelay: TimeInterval = 0.05
    private static let maxFocusAttempts = 10

    internal private(set) var fulfilledFocusRequestToken = -1
    private var focusTask: Task<Void, Never>?

    internal func cancelPendingFocusRequests() {
        focusTask?.cancel()
        focusTask = nil
    }

    internal func requestFocus(token: Int, for textField: UITextField) {
        guard fulfilledFocusRequestToken != token else { return }

        cancelPendingFocusRequests()
        focusTask = Task { @MainActor [weak self, weak textField] in
            guard let self else { return }

            let delay = UInt64(Self.focusRetryDelay * 1_000_000_000)
            for attempt in 0..<Self.maxFocusAttempts {
                guard !Task.isCancelled, let textField else { return }
                guard self.fulfilledFocusRequestToken != token else { return }

                if textField.isFirstResponder || (textField.window != nil && textField.becomeFirstResponder()) {
                    self.fulfilledFocusRequestToken = token
                    self.focusTask = nil
                    return
                }

                guard attempt + 1 < Self.maxFocusAttempts else { break }
                try? await Task.sleep(nanoseconds: delay)
            }

            self.focusTask = nil
        }
    }
}
