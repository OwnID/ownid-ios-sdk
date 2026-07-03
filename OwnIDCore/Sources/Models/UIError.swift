import Foundation

/// Error text prepared for an SDK operation screen.
///
/// SDK operation UI state uses this object when an error is already meant to be visible in that operation screen. Treat
/// ``localizedMessage`` as a display value resolved from ``errorCode`` for the current string set. If custom copy is
/// needed, use ``errorCode`` as a stable localization key and replace the message in the app layer.
///
/// This type describes presentation intent only. Use the typed operation or flow failure that produced the UI state for
/// semantic handling, retry decisions, and analytics.
public struct UIError: Equatable, Sendable, CustomStringConvertible {
    public let errorCode: ErrorCode

    public let localizedMessage: String

    public init(errorCode: ErrorCode, localizedMessage: String) {
        self.errorCode = errorCode
        self.localizedMessage = localizedMessage
    }

    public var description: String {
        "UIError(errorCode=\(errorCode), localizedMessage=\(localizedMessage))"
    }
}

extension ErrorCode {
    internal func toUIError(errorStrings: ErrorStrings) -> UIError {
        UIError(errorCode: self, localizedMessage: resolveLocalizedMessage(errorStrings: errorStrings))
    }
}
