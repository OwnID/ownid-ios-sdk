import Foundation
@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI

internal final class BottomSheetOperationUIContainerImpl: OperationUIContainer, @unchecked Sendable {
    private let instanceResolver: any DIContainerResolver
    private let presenter: any BottomSheetPresenter
    private let themeStore: OwnIDThemeStore
    private let languageTagsProvider: (any LanguageTagsProvider)?
    private let logger: OwnIDLogRouter?

    internal init(
        instanceResolver: any DIContainerResolver,
        presenter: any BottomSheetPresenter,
        themeStore: OwnIDThemeStore,
        languageTagsProvider: (any LanguageTagsProvider)?,
        logger: OwnIDLogRouter?
    ) {
        self.instanceResolver = instanceResolver
        self.presenter = presenter
        self.themeStore = themeStore
        self.languageTagsProvider = languageTagsProvider
        self.logger = logger
    }

    @MainActor
    internal func show<Controller: OperationController>(controller operationController: Controller) {
        presenter.show(
            themeStore: themeStore,
            onFailure: { reason in
                self.logger?.logW(
                    source: BottomSheetOperationUIContainerImpl.self,
                    prefix: "show",
                    message: "Startup failure reason=\(reason)"
                )
                operationController.abort(reason: reason)
            },
            content: { containerController -> AnyView in
                let content = OperationLifecycleHost(
                    instanceResolver: self.instanceResolver,
                    operationController: operationController,
                    renderController: operationController,
                    containerController: containerController,
                    errorTextProvider: nil
                )

                guard let languageTagsProvider = self.languageTagsProvider else {
                    return AnyView(content)
                }

                return AnyView(content.modifier(SDKLayoutDirectionModifier(languageTagsProvider: languageTagsProvider)))
            }
        )
    }
}

private struct SDKLayoutDirectionModifier: ViewModifier {
    @State private var layoutDirection: LayoutDirection = .leftToRight

    private let languageTagsProvider: any LanguageTagsProvider

    fileprivate init(languageTagsProvider: any LanguageTagsProvider) {
        self.languageTagsProvider = languageTagsProvider
    }

    fileprivate func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, layoutDirection)
            .taskCompat(id: "OwnIDSDKLayoutDirection") {
                for await tags in languageTagsProvider.languageTags {
                    let languageTag = tags.first ?? .default
                    switch NSLocale.characterDirection(forLanguage: languageTag.language) {
                    case .rightToLeft:
                        layoutDirection = .rightToLeft
                    default:
                        layoutDirection = .leftToRight
                    }
                }
            }
    }
}
