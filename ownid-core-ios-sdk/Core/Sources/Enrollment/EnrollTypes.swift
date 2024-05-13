import Combine

public extension OwnID {
    typealias EnrollEventPublisher = AnyPublisher<Result<Void, OwnID.CoreSDK.Error>, Never>
}
