import Foundation
import UIKit

/// A protocol that defines a social authentication provider.
///
/// Adopting types can handle sign-in with a particular social platform
/// by providing an implementation for `login(viewController:)`.
public protocol SocialProvider {
    init()
    
    /// Initiates the sign-in flow for the social provider.
    /// - Parameters:
    ///   - clientID: The identifier for the social provider client.
    ///   This is often used to hold the application’s client ID,
    ///   required by the social platform to handle authentication requests.
    ///   - viewController: The view controller from which
    ///   to present the social login interface.
    /// - Returns: A publisher that emits the result of the social login attempt,
    ///   allowing to handle success or failure.
    func login(clientID: String?, viewController: UIViewController?) -> OwnID.SocialResultPublisher
}
