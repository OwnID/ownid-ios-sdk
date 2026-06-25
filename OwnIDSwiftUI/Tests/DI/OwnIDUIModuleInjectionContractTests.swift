import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

struct OwnIDUIModuleInjectionContractTests {

    @MainActor
    @Test func `Direct UI module injection registers providers and UI capabilities`() throws {
        let container = DIContainerImpl(scopeName: "ui-module-test")
        container.register((any UIContextProvider).self, instance: ModuleTestUIContextProvider())

        try OwnIDUIModule.injectIntoInstanceContainer(container: container)

        try assertSwiftUIModuleRuntimeBindings(in: container)
    }

    @Test func `Default container registration keeps UI context provider as required dependency`() throws {
        let container = DIContainerImpl(scopeName: "ui-module-missing-context")

        try OwnIDUIModule.injectIntoInstanceContainer(container: container)

        #expect(container.getOrNil(type: OwnIDThemeStore.self) != nil)
        #expect(container.getOrNil(type: (any LoginIDCollectUIProvider).self) != nil)
        #expect(container.canResolve((any OperationUIContainer).self) == false)
        #expect(
            container.getUnsatisfiedDependencies(for: (any OperationUIContainer).self)?.contains {
                $0.contains("OperationUIContainer") && $0.contains("UIContextProvider")
            } == true
        )
    }
}
