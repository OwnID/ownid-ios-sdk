import Combine

public extension OwnID {
    typealias SocialResultPublisher = AnyPublisher<String, OwnID.CoreSDK.Error>
    typealias SocialEventPublisher = AnyPublisher<Result<(String, String?), OwnID.CoreSDK.Error>, Never>
}
