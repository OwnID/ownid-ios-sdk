import Foundation
@_spi(OwnIDInternal) import OwnIDCore

/// Registers optional UI bindings in an OwnID instance container.
///
/// This is an internal SDK module contract, not a public app integration contract. The module owns operation UI content,
/// SDK-owned presentation support, and theme propagation for the optional UI product. Apps customize operation content
/// through public UI APIs rather than by calling this module directly.
@objc
@_spi(OwnIDInternal) public final class OwnIDUIModule: NSObject, OwnIDModule {

    /// Injects the default UI dependencies into an OwnID instance container.
    ///
    /// The injected bindings are owned by the optional UI product. Core SDK runtime contracts remain owned by
    /// `OwnIDCore`.
    @_spi(OwnIDInternal) public static func injectIntoInstanceContainer(container: any DIContainer) throws {
        container.register(OwnIDThemeStore())

        container.registerFactory(dependencies: [(any UIContextProvider).self]) { resolver -> any BottomSheetPresenter in
            BottomSheetPresenterImpl(
                uiContextProvider: try resolver.getOrThrow(type: (any UIContextProvider).self),
                logger: container.getOrNil(type: OwnIDLogRouter.self)
            )
        }

        container.registerFactory(dependencies: [(any BottomSheetPresenter).self, OwnIDThemeStore.self]) {
            resolver -> any OperationUIContainer in
            BottomSheetOperationUIContainerImpl(
                instanceResolver: resolver,
                presenter: try resolver.getOrThrow(type: (any BottomSheetPresenter).self),
                themeStore: try resolver.getOrThrow(type: OwnIDThemeStore.self),
                languageTagsProvider: resolver.getOrNil(type: (any LanguageTagsProvider).self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self)
            )
        }

        container.registerFactory { resolver -> any LoginIDCollectUIProvider in LoginIDCollectUIDefaultProvider() }

        container.registerFactory(dependencies: [(any LoginIDCollectUIProvider).self, (any OperationUIContainer).self]) {
            resolver -> any LoginIDCollectUI in
            LoginIDCollectUIImpl { @MainActor controller in
                try resolver.getOrThrow(type: (any OperationUIContainer).self).show(controller: controller)
            }
        }

        container.registerFactory { resolver -> any EmailVerificationUIProvider in EmailVerificationUIDefaultProvider() }

        container.registerFactory(dependencies: [(any EmailVerificationUIProvider).self, (any OperationUIContainer).self]) {
            resolver -> any EmailVerificationUI in
            EmailVerificationUIImpl { @MainActor controller in
                try resolver.getOrThrow(type: (any OperationUIContainer).self).show(controller: controller)
            }
        }

        container.registerFactory { resolver -> any PhoneVerificationUIProvider in PhoneVerificationUIDefaultProvider() }

        container.registerFactory(dependencies: [(any PhoneVerificationUIProvider).self, (any OperationUIContainer).self]) {
            resolver -> any PhoneVerificationUI in
            PhoneVerificationUIImpl { @MainActor controller in
                try resolver.getOrThrow(type: (any OperationUIContainer).self).show(controller: controller)
            }
        }
    }
}
