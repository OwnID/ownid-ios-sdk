import Foundation

/// Internal cause category for unexpected API failures.
///
/// The category supports SDK diagnostics and server logging. It is not part of the public app-facing recovery contract.
internal enum APIUnexpectedCause: Sendable {
    /// Transport failure returned by the network capability before a usable HTTP response was available.
    case network(NetworkResponse.Fail.NetworkError)

    /// HTTP response or successful response body that did not match the endpoint contract handled by the SDK.
    case apiContract(APIContract)

    /// Local SDK setup or execution failure outside the HTTP response mapping layer.
    case runtime(any Error & Sendable)

    /// Details for response-shape or status mismatches in the API mapping layer.
    internal struct APIContract: Sendable {
        internal let failure: NetworkResponse.Fail
        internal let error: (any Error & Sendable)?

        internal init(failure: NetworkResponse.Fail, error: (any Error & Sendable)? = nil) {
            self.failure = failure
            self.error = error
        }
    }
}

/// Sendable wrapper used as the underlying error for endpoint `unexpected` API failures.
internal struct APIUnexpectedError: Error, Sendable, CustomStringConvertible {
    internal let cause: APIUnexpectedCause

    internal init(cause: APIUnexpectedCause) {
        self.cause = cause
    }

    internal var description: String {
        switch cause {
        case .network(let failure):
            return String(describing: NetworkResponse.Fail.networkError(failure))
        case .apiContract(let contract):
            return String(describing: contract.failure)
        case .runtime(let error):
            return String(describing: error)
        }
    }
}
