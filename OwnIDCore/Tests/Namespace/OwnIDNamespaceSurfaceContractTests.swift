import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct OwnIDNamespaceSurfaceContractTests {
    @Test func `Instance context scoping returns child context without mutating current scope`() throws {
        let instance = makeInstance()

        #expect(instance.container.getOrNil(type: Context.self) == nil)

        _ = instance.setContext { builder in
            builder.authz = .fromToken("root-token")
            builder.accountDisplayName = "Root User"
        }

        let scoped = instance.withContext("child") { builder in
            builder.authz = .start(LoginID(id: "child@example.test", type: .email))
        }

        let rootContext = try #require(instance.container.getOrNil(type: Context.self))
        #expect(rootContext.accessToken == AccessToken(token: "root-token"))
        #expect(rootContext.accountDisplayName == "Root User")

        let scopedContext = try #require(scoped.container.getOrNil(type: Context.self))
        #expect(scopedContext.loginID == LoginID(id: "child@example.test", type: .email))
        #expect(scopedContext.accountDisplayName == nil)
    }

    @Test func `Instance context override mutates current scope and clear preserves providers`() throws {
        let instance = makeInstance()

        _ = instance.setContext { builder in
            builder.authz = .fromToken("initial-token")
            builder.accountDisplayName = "Initial User"
        }

        _ = instance.setContext { builder in
            builder.accountDisplayName = "Renamed User"
        }

        let mergedContext = try #require(instance.container.getOrNil(type: Context.self))
        #expect(mergedContext.accessToken == AccessToken(token: "initial-token"))
        #expect(mergedContext.accountDisplayName == "Renamed User")

        _ = instance.setProviders { registrar in
            registrar.sessionCreate { builder in
                builder.create { _ in .success(SessionOutput(session: "provider")) }
            }
        }
        #expect(instance.container.getOrNil(type: (any SessionCreate).self) != nil)

        _ = instance.clearContext()

        #expect(instance.container.getOrNil(type: Context.self) == nil)
        #expect(instance.container.getOrNil(type: (any SessionCreate).self) != nil)
    }

    private func makeInstance() -> OwnIDInstanceImpl {
        let container = DIContainerImpl(scopeName: "OwnIDNamespaceSurfaceContractTests")
        container.register(WebBridgePluginFactoryStoreImpl.self, instance: WebBridgePluginFactoryStoreImpl())
        return OwnIDInstanceImpl(container: container)
    }

}
