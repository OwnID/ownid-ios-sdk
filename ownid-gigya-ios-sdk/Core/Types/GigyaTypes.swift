import Foundation
import OwnIDCoreSDK
import Combine
import Gigya

public extension OwnID.GigyaSDK {
    typealias EventPublisher = AnyPublisher<OwnID.LoginResult, OwnID.CoreSDK.CoreErrorLogWrapper>
}
