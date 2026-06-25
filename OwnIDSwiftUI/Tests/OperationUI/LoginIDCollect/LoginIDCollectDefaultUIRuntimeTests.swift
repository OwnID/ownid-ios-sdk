import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@MainActor
@Suite(.serialized)
struct LoginIDCollectDefaultUIRuntimeTests {

    @Test(arguments: [LoginIDType.email, .phoneNumber, .userName])
    func `Login ID field applies input traits for the collected type`(loginIDType: LoginIDType) async throws {
        let host = SwiftUIRuntimeHost(
            rootView: LoginIDCollectRuntimeFixture(loginIDTypes: [loginIDType])
        )
        defer { host.close() }
        await host.settle()

        let textField = try #require(host.textFields().first)

        #expect(textField.keyboardType == expectedKeyboardType(for: loginIDType))
        #expect(textField.textContentType == expectedTextContentType(for: loginIDType))
        #expect(textField.returnKeyType == .continue)
        #expect(textField.autocorrectionType == .no)
        #expect(textField.autocapitalizationType == .none)
        #expect(textField.spellCheckingType == .no)
        #expect(textField.semanticContentAttribute == .forceLeftToRight)
        #expect(textField.textAlignment == .left)
    }

    @Test func `Login ID field applies semantic colors from OwnID theme`() async throws {
        guard #available(iOS 14.0, *) else { return }

        let primary = UIColor(red: 0.13, green: 0.31, blue: 0.72, alpha: 1)
        let onSurface = UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
        let onSurfaceVariant = UIColor(red: 0.42, green: 0.43, blue: 0.44, alpha: 1)
        let theme = loginIDFieldTheme(
            primary: primary,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant
        )
        let host = SwiftUIRuntimeHost(
            rootView: LoginIDCollectRuntimeFixture()
                .environment(\.ownIDTheme, theme)
        )
        defer { host.close() }
        await host.settle()

        let textField = try #require(host.textFields().first)
        let placeholderColor = try #require(
            textField.attributedPlaceholder?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        )

        #expect(textField.tintColor.ownIDTestIsEqual(to: primary))
        #expect(textField.textColor?.ownIDTestIsEqual(to: onSurface) == true)
        #expect(placeholderColor.ownIDTestIsEqual(to: onSurfaceVariant))
    }

    @Test func `Login ID typing updates state and validation error recovers on edit`() async throws {
        let recorder = LoginIDCollectRuntimeRecorder()
        let host = SwiftUIRuntimeHost(
            rootView: LoginIDCollectRuntimeFixture(recorder: recorder)
        )
        defer { host.close() }
        await host.settle()

        let textField = try #require(host.textFields().first)

        await enterText("invalid", in: textField, host: host)
        #expect(recorder.changedValues == ["invalid"])

        try submitReturn(on: textField)
        await host.settle()
        #expect(recorder.continuedValues == ["invalid"])
        #expect(host.accessibilityLabels().contains("Enter a valid email"))
        #expect(textField.accessibilityHint == "Enter a valid email")

        await enterText("user@example.test", in: textField, host: host)
        #expect(recorder.changedValues == ["invalid", "user@example.test"])
        #expect(!host.accessibilityLabels().contains("Enter a valid email"))
        #expect(textField.accessibilityHint == nil)
    }

    @Test func `Login ID continue and cancel controls invoke callbacks`() async throws {
        let recorder = LoginIDCollectRuntimeRecorder()
        let host = SwiftUIRuntimeHost(
            rootView: LoginIDCollectRuntimeFixture(recorder: recorder)
        )
        defer { host.close() }
        await host.settle()

        let textField = try #require(host.textFields().first)
        await enterText("user@example.test", in: textField, host: host)

        try activateControl(labeled: "Continue", in: host)
        try activateControl(labeled: "Cancel", in: host)
        await host.settle()

        #expect(recorder.continuedValues == ["user@example.test"])
        #expect(recorder.cancelCount == 1)
    }

    @available(iOS 15.0, *)
    @Test func `Login ID layout reports bounded fitting size under constrained width and large Dynamic Type`() async throws {
        let host = SwiftUIRuntimeHost(
            rootView: LoginIDCollectRuntimeFixture(
                title: "Enter your email address or phone number",
                message: "Use the same login ID you normally use to continue securely.",
                placeholder: "Email or phone number"
            )
            .environment(\.dynamicTypeSize, .accessibility3),
            size: CGSize(width: 220, height: 520)
        )
        defer { host.close() }
        await host.settle()

        host.assertFittingSize(.constrainedOperationUI)
        let textField = try #require(host.textFields().first)

        host.assertLaidOut(textField, maxWidth: 480)
        #expect(textField.adjustsFontForContentSizeCategory)
    }
}

@MainActor
private struct LoginIDCollectRuntimeFixture: View {
    let loginIDTypes: [LoginIDType]
    let recorder: LoginIDCollectRuntimeRecorder

    @State private var loginIDValue = ""
    @State private var error: UIError?

    init(
        loginIDTypes: [LoginIDType] = [.email],
        recorder: LoginIDCollectRuntimeRecorder = LoginIDCollectRuntimeRecorder(),
        title: String = "Enter your email",
        message: String = "to receive a one-time code",
        placeholder: String = "Email"
    ) {
        self.loginIDTypes = loginIDTypes
        self.recorder = recorder
        self.title = title
        self.message = message
        self.placeholder = placeholder
    }

    private let title: String
    private let message: String
    private let placeholder: String

    var body: some View {
        LoginIDCollectDefaultView(
            uiState: LoginIDCollectUIState(
                loginIDValue: loginIDValue,
                collectableLoginIDTypes: loginIDTypes,
                error: error,
                onLoginIDChange: { value in
                    MainActor.assumeIsolated {
                        loginIDValue = value
                        error = nil
                        recorder.recordChangedValue(value)
                    }
                },
                onContinue: {
                    MainActor.assumeIsolated {
                        recorder.recordContinue(loginIDValue)
                        if !loginIDValue.contains("@") {
                            error = UIError(errorCode: .loginIDValidationFailed, localizedMessage: "Invalid login ID")
                        }
                    }
                },
                onCancel: {
                    MainActor.assumeIsolated {
                        recorder.recordCancel()
                    }
                }
            ),
            uiStrings: LoginIDCollectStrings(
                title: title,
                message: message,
                placeholder: placeholder,
                cancel: "Cancel",
                cta: "Continue",
                error: "Enter a valid email"
            ),
            isReadyForInitialFocus: false
        )
    }
}

@MainActor
private final class LoginIDCollectRuntimeRecorder {
    private(set) var changedValues: [String] = []
    private(set) var continuedValues: [String] = []
    private(set) var cancelCount = 0

    func recordChangedValue(_ value: String) {
        changedValues.append(value)
    }

    func recordContinue(_ value: String) {
        continuedValues.append(value)
    }

    func recordCancel() {
        cancelCount += 1
    }
}

private func expectedKeyboardType(for loginIDType: LoginIDType) -> UIKeyboardType {
    switch loginIDType {
    case .email:
        .emailAddress
    case .phoneNumber:
        .phonePad
    default:
        .default
    }
}

private func expectedTextContentType(for loginIDType: LoginIDType) -> UITextContentType? {
    switch loginIDType {
    case .email:
        .emailAddress
    case .phoneNumber:
        .telephoneNumber
    case .userName:
        .username
    default:
        nil
    }
}

private func loginIDFieldTheme(
    primary: UIColor,
    onSurface: UIColor,
    onSurfaceVariant: UIColor
) -> OwnIDTheme {
    var colors = OwnIDTheme.capture(colorScheme: .light).colors
    colors.primary = Color(uiColorCompat: primary)
    colors.onSurface = Color(uiColorCompat: onSurface)
    colors.onSurfaceVariant = Color(uiColorCompat: onSurfaceVariant)
    return OwnIDTheme(colors: colors)
}
