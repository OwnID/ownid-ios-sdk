import Foundation

/// SDK module entry point for registering dependencies into an instance container.
///
/// This is an internal SDK module contract, not a public app integration contract. Implementations own only their
/// module's bindings. They may depend on Core services and may replace module-owned fallback bindings when that is the
/// intended extension point.
@_spi(OwnIDInternal) public protocol OwnIDModule {
    /// Registers this module's dependencies into the given container.
    ///
    /// - Throws: If this module cannot complete registration. The injector retains completed registrations, logs the
    ///   failure, skips this module's remaining work, and continues with later discovered modules.
    static func injectIntoInstanceContainer(container: any DIContainer) throws
}

/// Discovers and injects optional SDK modules into an instance container at runtime.
///
/// This is an internal SDK module contract, not a public app integration contract. SDK-owned module classes present in
/// the process may register dependencies for their own product boundary. Injection is best-effort and nontransactional:
/// registrations completed before a thrown error remain, only that module's remaining work is skipped, the failure is
/// logged, and later discovered modules continue.
@_spi(OwnIDInternal) public final class OwnIDModuleInjector {
    private static let possiblePluginClassNames = ["OwnIDSwiftUI.OwnIDUIModule", "OwnIDReactNativeCoreModule"]

    internal static func injectIntoInstanceContainer(
        container: any DIContainer,
        classNames: [String] = possiblePluginClassNames,
        classResolver: (String) -> AnyClass? = NSClassFromString
    ) {
        let logger = container.getOrNil(type: OwnIDLogRouter.self)
        let modules = resolveModuleTypes(classNames: classNames, classResolver: classResolver, logger: logger)

        for moduleType in modules {
            do {
                try moduleType.injectIntoInstanceContainer(container: container)
            } catch {
                logger?.logW(
                    source: Self.self,
                    prefix: "injectIntoInstanceContainer",
                    message: "Failed for: \(String(describing: moduleType))",
                    cause: error
                )
            }
        }
    }

    private static func resolveModuleTypes(
        classNames: [String],
        classResolver: (String) -> AnyClass?,
        logger: OwnIDLogRouter?
    ) -> [any OwnIDModule.Type] {
        var modules: [any OwnIDModule.Type] = []

        for className in classNames {
            guard let anyClass = classResolver(className) else {
                logger?.logV(source: Self.self, prefix: "moduleLookup", message: "Module class \(className) not found")
                continue
            }

            guard let moduleType = anyClass as? (any OwnIDModule.Type) else {
                logger?.logW(source: Self.self, prefix: "moduleLookup", message: "Class \(className) does not conform to OwnIDModule")
                continue
            }

            if modules.contains(where: { ObjectIdentifier($0) == ObjectIdentifier(moduleType) }) { continue }
            modules.append(moduleType)
        }

        return modules
    }
}
