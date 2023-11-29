//
//  OwnIDGigyaWebBridgeConfiguration.swift
//  private-ownid-gigya-ios-sdk
//
//  Created by user on 13.10.2023.
//

import Gigya

extension OwnID.GigyaSDK {
    public static func configureWebBridge() {
        Gigya.getContainer().register(service: GigyaWebBridge<GigyaAccount>.self) { resolver in
            let config = resolver.resolve(GigyaConfig.self)
            let persistenceService = resolver.resolve(PersistenceService.self)
            let sessionService = resolver.resolve(SessionServiceProtocol.self)
            let businessService = resolver.resolve(BusinessApiServiceProtocol.self)
            let wbBridgeInterruptionManager = resolver.resolve(WebBridgeInterruptionResolverFactoryProtocol.self)

            return OwnIDGigyaWebBridge(config: config!, persistenceService: persistenceService!, sessionService: sessionService!, businessApiService: businessService!, interruptionManager: wbBridgeInterruptionManager!)
        }
    }
}
