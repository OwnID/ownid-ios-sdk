import Foundation
import OwnIDCore
import Testing

struct ErrorValueModelContractTests {
    private let modelJSON = ModelJSON()

    @Test func `Error code raw values description and Codable values are stable`() throws {
        let expectedRawValues: [ErrorCode: String] = [
            .aborted: "aborted",
            .cancelNotSupported: "cancel_not_supported",
            .deviceNotSupported: "device_not_supported",
            .domElementNotFound: "dom_element_not_found",
            .emptyLoginID: "empty_login_id",
            .forbidden: "forbidden",
            .integrationError: "integration_error",
            .invalidArgument: "invalid_argument",
            .invalidChallenge: "invalid_challenge",
            .loginIDTypeNotSupported: "login_id_type_not_supported",
            .loginIDValidationFailed: "login_id_validation_failed",
            .loginWithPasswordFailed: "login_with_password_failed",
            .maximumAttemptsReached: "maximum_attempts_reached",
            .maximumChallengesReached: "maximum_challenges_reached",
            .maximumResendAttemptsReached: "maximum_resend_attempts_reached",
            .missingCapabilityProvider: "missing_capability_provider",
            .missingChannel: "missing_channel",
            .network: "network",
            .noApplicablePasskeys: "no_applicable_passkeys",
            .notificationBlocked: "notification_blocked",
            .oidcFailed: "oidc_failed",
            .passkeyAlreadyRegistered: "passkey_already_registered",
            .passkeyNotCreated: "passkey_not_created",
            .passkeysNotSupported: "passkeys_not_supported",
            .screensNotReady: "screens_not_ready",
            .sessionNotEstablished: "session_not_established",
            .timeout: "timeout",
            .unauthorized: "unauthorized",
            .unknown: "unknown",
            .userBlocked: "user_blocked",
            .userChanged: "user_changed",
            .userNotFound: "user_not_found",
            .verificationCodeWrong: "verification_code_wrong",
            .widgetAlreadyExists: "widget_already_exists",
        ]

        #expect(Set(ErrorCode.allCases).count == expectedRawValues.count)

        for errorCode in ErrorCode.allCases {
            let rawValue = try #require(expectedRawValues[errorCode])
            #expect(errorCode.rawValue == rawValue)
            #expect(errorCode.value == rawValue)
            #expect(errorCode.description == rawValue)
            #expect(try modelJSON.string(encoding: errorCode) == #""\#(rawValue)""#)
            #expect(try modelJSON.decoder.decode(ErrorCode.self, from: Data(#""\#(rawValue)""#.utf8)) == errorCode)
        }

        #expect(throws: (any Error).self) {
            try modelJSON.decoder.decode(ErrorCode.self, from: Data(#""not_a_public_code""#.utf8))
        }
    }

    @Test func `Error strings map every error code to matching property`() {
        let errorStrings = ErrorStrings(
            aborted: ErrorCode.aborted.rawValue,
            cancelNotSupported: ErrorCode.cancelNotSupported.rawValue,
            deviceNotSupported: ErrorCode.deviceNotSupported.rawValue,
            domElementNotFound: ErrorCode.domElementNotFound.rawValue,
            emptyLoginID: ErrorCode.emptyLoginID.rawValue,
            forbidden: ErrorCode.forbidden.rawValue,
            integrationError: ErrorCode.integrationError.rawValue,
            invalidArgument: ErrorCode.invalidArgument.rawValue,
            invalidChallenge: ErrorCode.invalidChallenge.rawValue,
            loginIDTypeNotSupported: ErrorCode.loginIDTypeNotSupported.rawValue,
            loginIDValidationFailed: ErrorCode.loginIDValidationFailed.rawValue,
            loginWithPasswordFailed: ErrorCode.loginWithPasswordFailed.rawValue,
            maximumAttemptsReached: ErrorCode.maximumAttemptsReached.rawValue,
            maximumChallengesReached: ErrorCode.maximumChallengesReached.rawValue,
            maximumResendAttemptsReached: ErrorCode.maximumResendAttemptsReached.rawValue,
            missingCapabilityProvider: ErrorCode.missingCapabilityProvider.rawValue,
            missingChannel: ErrorCode.missingChannel.rawValue,
            network: ErrorCode.network.rawValue,
            noApplicablePasskeys: ErrorCode.noApplicablePasskeys.rawValue,
            notificationBlocked: ErrorCode.notificationBlocked.rawValue,
            oidcFailed: ErrorCode.oidcFailed.rawValue,
            passkeyAlreadyRegistered: ErrorCode.passkeyAlreadyRegistered.rawValue,
            passkeyNotCreated: ErrorCode.passkeyNotCreated.rawValue,
            passkeysNotSupported: ErrorCode.passkeysNotSupported.rawValue,
            screensNotReady: ErrorCode.screensNotReady.rawValue,
            sessionNotEstablished: ErrorCode.sessionNotEstablished.rawValue,
            timeout: ErrorCode.timeout.rawValue,
            unauthorized: ErrorCode.unauthorized.rawValue,
            unknown: ErrorCode.unknown.rawValue,
            userBlocked: ErrorCode.userBlocked.rawValue,
            userChanged: ErrorCode.userChanged.rawValue,
            userNotFound: ErrorCode.userNotFound.rawValue,
            verificationCodeWrong: ErrorCode.verificationCodeWrong.rawValue,
            widgetAlreadyExists: ErrorCode.widgetAlreadyExists.rawValue
        )

        for errorCode in ErrorCode.allCases {
            #expect(errorStrings.getString(for: errorCode) == errorCode.rawValue)
        }
    }

    @Test func `Default error strings provide display value for every error code`() {
        for errorCode in ErrorCode.allCases {
            let defaultString = ErrorStrings.default.getString(for: errorCode)

            #expect(!defaultString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test func `UI error keeps display message in equality and description`() {
        let error = UIError(errorCode: .network, localizedMessage: "Network unavailable")

        #expect(error == UIError(errorCode: .network, localizedMessage: "Network unavailable"))
        #expect(error != UIError(errorCode: .network, localizedMessage: "Different"))
        #expect(error.description == "UIError(errorCode=network, localizedMessage=Network unavailable)")
    }

}
