import Gigya

extension OwnID.GigyaSDK {
    public static func configureWebBridge<T: GigyaAccountProtocol>(accountType: T.Type = GigyaAccount.self) {
        Gigya.getContainer().register(service: GigyaWebBridge<T>.self) { resolver in
            let config = resolver.resolve(GigyaConfig.self)
            let persistenceService = resolver.resolve(PersistenceService.self)
            let sessionService = resolver.resolve(SessionServiceProtocol.self)
            let businessService = resolver.resolve(BusinessApiServiceProtocol.self)
            let wbBridgeInterruptionManager = resolver.resolve(WebBridgeInterruptionResolverFactoryProtocol.self)

            return OwnIDGigyaWebBridge(config: config!, persistenceService: persistenceService!, sessionService: sessionService!, businessApiService: businessService!, interruptionManager: wbBridgeInterruptionManager!)
        }
    }
}
