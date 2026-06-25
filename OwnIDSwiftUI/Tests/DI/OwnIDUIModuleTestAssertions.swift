import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@MainActor
func assertSwiftUIModuleRuntimeBindings(in container: any DIContainer) throws {
    #expect(container.getOrNil(type: OwnIDThemeStore.self) != nil)
    #expect(container.getOrNil(type: (any BottomSheetPresenter).self) != nil)
    #expect(container.getOrNil(type: (any OperationUIContainer).self) is BottomSheetOperationUIContainerImpl)
    #expect(container.getOrNil(type: (any LoginIDCollectUIProvider).self) is LoginIDCollectUIDefaultProvider)
    #expect(container.getOrNil(type: (any EmailVerificationUIProvider).self) is EmailVerificationUIDefaultProvider)
    #expect(container.getOrNil(type: (any PhoneVerificationUIProvider).self) is PhoneVerificationUIDefaultProvider)

    let operationUIContainer = CapturingOperationUIContainer()
    container.register(
        (any OperationUIContainer).self,
        instance: operationUIContainer as any OperationUIContainer
    )

    let loginUI = try container.getOrThrow(type: (any LoginIDCollectUI).self)
    let emailUI = try container.getOrThrow(type: (any EmailVerificationUI).self)
    let phoneUI = try container.getOrThrow(type: (any PhoneVerificationUI).self)

    #expect(loginUI is LoginIDCollectUIImpl)
    #expect(emailUI is EmailVerificationUIImpl)
    #expect(phoneUI is PhoneVerificationUIImpl)

    #expect(loginUI.start(controller: StubLoginIDCollectOperationController()) == nil)
    #expect(emailUI.start(controller: StubEmailVerificationOperationController()) == nil)
    #expect(phoneUI.start(controller: StubPhoneVerificationOperationController()) == nil)
    #expect(
        operationUIContainer.shownOperationIDs == [
            OperationID(type: .loginIDCollect, id: "login-id-collect"),
            OperationID(type: .emailVerification, id: "email-verification"),
            OperationID(type: .phoneNumberVerification, id: "phone-verification"),
        ]
    )
}

final class ModuleTestUIContextProvider: UIContextProvider, @unchecked Sendable {
    @MainActor
    func activeWindow() -> UIWindow? {
        nil
    }

    @MainActor
    func topMostViewController(_ window: UIWindow?) -> UIViewController? {
        nil
    }
}
