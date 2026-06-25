import Foundation
import OwnIDSwiftUI
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

private let widgetStreamTimeoutNanoseconds: UInt64 = 5_000_000_000

private enum WidgetStreamWaitResult<Element: Sendable>: Sendable {
    case element(Element?)
    case timedOut
}

struct WidgetLoginIDCase: Sendable {
    let raw: String?
    let normalized: String?

    static let loginNormalizationCases: [WidgetLoginIDCase] = normalizationCases(for: "user@example.com")
    static let createPasskeyNormalizationCases: [WidgetLoginIDCase] = normalizationCases(for: "new@example.com")

    private static func normalizationCases(for normalizedLoginID: String) -> [WidgetLoginIDCase] {
        [
            WidgetLoginIDCase(raw: nil, normalized: nil),
            WidgetLoginIDCase(raw: "", normalized: nil),
            WidgetLoginIDCase(raw: "   \n\t", normalized: nil),
            WidgetLoginIDCase(raw: "  \(normalizedLoginID) \n", normalized: normalizedLoginID),
        ]
    }
}

enum LoginWidgetTerminalResult: CaseIterable, Sendable {
    case success
    case canceled
    case failure

    var result: FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure> {
        switch self {
        case .success:
            .success(makeLoginResponse())
        case .canceled:
            .canceled(.userClose(details: "dismissed"))
        case .failure:
            .failure(makeLoginFailure())
        }
    }
}

enum CreatePasskeyWidgetTerminalResult: CaseIterable, Sendable {
    case login
    case createPasskey
    case canceled
    case failure

    var result: FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure> {
        switch self {
        case .login:
            .success(.login(makeLoginResponse(id: "existing@example.com")))
        case .createPasskey:
            .success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.com")))
        case .canceled:
            .canceled(.userClose(details: "dismissed"))
        case .failure:
            .failure(makeCreatePasskeyFailure())
        }
    }
}

@MainActor
func makeLoginViewModel(
    starter: @escaping @MainActor @Sendable (BoostFlowContext) throws -> any BoostLoginFlowController
) -> OwnIDLoginWidgetViewModel {
    OwnIDLoginWidgetViewModel(boostLoginFlowStarter: starter)
}

@MainActor
func makeCreatePasskeyViewModel(
    starter: @escaping @MainActor @Sendable (BoostFlowContext) throws -> any BoostCreatePasskeyFlowController
) -> OwnIDCreatePasskeyWidgetViewModel {
    OwnIDCreatePasskeyWidgetViewModel(boostCreatePasskeyFlowStarter: starter)
}

func makeLoginResponse(id: String = "user@example.com") -> BoostFlowLoginResponse {
    BoostFlowLoginResponse(
        loginID: LoginID(id: id, type: .email),
        authMethod: .passkey,
        accessToken: AccessToken(token: "access-token"),
        sessionPayload: #"{"ok":true}"#
    )
}

func makeCreatePasskeyResponse(id: String = "new@example.com") -> BoostFlowCreatePasskeyResponse {
    BoostFlowCreatePasskeyResponse(
        loginID: LoginID(id: id, type: .email),
        proofToken: ProofToken(token: "proof-token"),
        ownIdData: #"{"ownId":true}"#
    )
}

func makeLoginFailure(message: String = "login failed") -> BoostLoginFlowFailure {
    .unexpected(errorCode: .integrationError, message: message)
}

func makeCreatePasskeyFailure(message: String = "create passkey failed") -> BoostCreatePasskeyFlowFailure {
    .unexpected(errorCode: .integrationError, message: message)
}

func expectWidgetContext(
    _ context: BoostFlowContext?,
    normalizedLoginID: String?,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let context = try #require(context, "Expected widget flow context", sourceLocation: sourceLocation)
    #expect(context.rawLoginID == normalizedLoginID, sourceLocation: sourceLocation)
    #expect(context.loginID == nil, sourceLocation: sourceLocation)
    #expect(context.source == .widgetButton, sourceLocation: sourceLocation)
}

func loginResponse(from effect: OwnIDLoginWidgetViewModel.UIEffect) -> BoostFlowLoginResponse? {
    guard case .login(let response) = effect else { return nil }
    return response
}

func loginError(from effect: OwnIDLoginWidgetViewModel.UIEffect) -> BoostLoginFlowFailure? {
    guard case .error(let error) = effect else { return nil }
    return error
}

func loginResponse(from effect: OwnIDCreatePasskeyWidgetViewModel.UIEffect) -> BoostFlowLoginResponse? {
    guard case .login(let response) = effect else { return nil }
    return response
}

func createPasskeyResponse(
    from effect: OwnIDCreatePasskeyWidgetViewModel.UIEffect
) -> BoostFlowCreatePasskeyResponse? {
    guard case .createPasskey(let response) = effect else { return nil }
    return response
}

func createPasskeyError(from effect: OwnIDCreatePasskeyWidgetViewModel.UIEffect) -> BoostCreatePasskeyFlowFailure? {
    guard case .error(let error) = effect else { return nil }
    return error
}

func cancellationReason(from effect: OwnIDLoginWidgetViewModel.UIEffect) -> Reason? {
    guard case .canceled(let reason) = effect else { return nil }
    return reason
}

func cancellationReason(from effect: OwnIDCreatePasskeyWidgetViewModel.UIEffect) -> Reason? {
    guard case .canceled(let reason) = effect else { return nil }
    return reason
}

func isResetRequested(_ effect: OwnIDCreatePasskeyWidgetViewModel.UIEffect) -> Bool {
    guard case .resetRequested = effect else { return false }
    return true
}

struct WidgetStarterError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        self.errorDescription = message
    }
}

final class ImmediateLoginController: BoostLoginFlowController, @unchecked Sendable {
    private let result: FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>

    init(_ result: FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>) {
        self.result = result
    }

    func abort(reason: Reason) {}

    func whenSettled() async -> FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure> {
        result
    }
}

final class ImmediateCreatePasskeyController: BoostCreatePasskeyFlowController, @unchecked Sendable {
    private let result: FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure>

    init(_ result: FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure>) {
        self.result = result
    }

    func abort(reason: Reason) {}

    func whenSettled() async -> FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure> {
        result
    }
}

final class RunningLoginController: BoostLoginFlowController, @unchecked Sendable {
    private let settlement = CancellablePendingValue(
        FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>.canceled(.userClose(details: "test canceled"))
    )
    private(set) var abortReasonDescriptions: [String] = []

    func abort(reason: Reason) {
        abortReasonDescriptions.append(reason.description)
    }

    func whenSettled() async -> FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure> {
        await settlement.wait()
    }
}

final class RunningCreatePasskeyController: BoostCreatePasskeyFlowController, @unchecked Sendable {
    private let settlement = CancellablePendingValue(
        FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure>.canceled(.userClose(details: "test canceled"))
    )
    private(set) var abortReasonDescriptions: [String] = []

    func abort(reason: Reason) {
        abortReasonDescriptions.append(reason.description)
    }

    func whenSettled() async -> FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure> {
        await settlement.wait()
    }
}

final class DeferredLoginController: BoostLoginFlowController, @unchecked Sendable {
    private let store = DeferredFlowResultStore<BoostFlowLoginResponse, BoostLoginFlowFailure>()

    func abort(reason: Reason) {}

    func whenSettled() async -> FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure> {
        await store.wait()
    }

    func settle(_ result: FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>) async {
        await store.resolve(result)
    }
}

final class DeferredCreatePasskeyController: BoostCreatePasskeyFlowController, @unchecked Sendable {
    private let store = DeferredFlowResultStore<BoostFlowResponse, BoostCreatePasskeyFlowFailure>()

    func abort(reason: Reason) {}

    func whenSettled() async -> FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure> {
        await store.wait()
    }

    func settle(_ result: FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure>) async {
        await store.resolve(result)
    }
}

final class RecordingBoostLoginFlow: BoostLoginFlow, @unchecked Sendable {
    private let recorder: WidgetFlowStartRecorder<any BoostLoginFlowController>

    init(controllers: [any BoostLoginFlowController]) {
        self.recorder = WidgetFlowStartRecorder(controllers: controllers)
    }

    var startCount: Int { recorder.startCount }

    func context(at index: Int) -> BoostFlowContext? {
        recorder.context(at: index)
    }

    func start(_ context: BoostFlowContext) -> any BoostLoginFlowController {
        recorder.start(
            context,
            fallback: ImmediateLoginController(.failure(makeLoginFailure(message: "Missing login controller")))
        )
    }
}

final class RecordingBoostCreatePasskeyFlow: BoostCreatePasskeyFlow, @unchecked Sendable {
    private let recorder: WidgetFlowStartRecorder<any BoostCreatePasskeyFlowController>

    init(controllers: [any BoostCreatePasskeyFlowController]) {
        self.recorder = WidgetFlowStartRecorder(controllers: controllers)
    }

    var startCount: Int { recorder.startCount }

    func context(at index: Int) -> BoostFlowContext? {
        recorder.context(at: index)
    }

    func start(_ context: BoostFlowContext) -> any BoostCreatePasskeyFlowController {
        recorder.start(
            context,
            fallback: ImmediateCreatePasskeyController(
                .failure(makeCreatePasskeyFailure(message: "Missing create-passkey controller"))
            )
        )
    }
}

private final class WidgetFlowStartRecorder<Controller: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var controllers: [Controller]
    private var recordedContexts: [BoostFlowContext] = []

    init(controllers: [Controller]) {
        self.controllers = controllers
    }

    var startCount: Int {
        lock.withLock { recordedContexts.count }
    }

    func context(at index: Int) -> BoostFlowContext? {
        lock.withLock {
            guard recordedContexts.indices.contains(index) else { return nil }
            return recordedContexts[index]
        }
    }

    func start(_ context: BoostFlowContext, fallback: @autoclosure () -> Controller) -> Controller {
        lock.withLock {
            recordedContexts.append(context)
            guard !controllers.isEmpty else { return fallback() }
            return controllers.removeFirst()
        }
    }
}

private actor DeferredFlowResultStore<Success: Sendable, Failure: FlowFailure> {
    private var result: FlowResult<Success, Failure>?
    private var waiters: [CheckedContinuation<FlowResult<Success, Failure>, Never>] = []

    func wait() async -> FlowResult<Success, Failure> {
        if let result {
            return result
        }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func resolve(_ result: FlowResult<Success, Failure>) {
        guard self.result == nil else { return }
        self.result = result
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }
}

func nextElement<S: AsyncSequence>(
    from sequence: S,
    _ description: Comment
) async throws -> S.Element where S: Sendable, S.Element: Sendable {
    let element = try await nextOptionalElement(from: sequence, description)
    return try #require(element, description)
}

func nextOptionalElement<S: AsyncSequence>(
    from sequence: S,
    _ description: Comment
) async throws -> S.Element? where S: Sendable, S.Element: Sendable {
    let result = try await withThrowingTaskGroup(of: WidgetStreamWaitResult<S.Element>.self) { group in
        group.addTask {
            for try await element in sequence {
                return .element(element)
            }
            return .element(nil)
        }
        group.addTask {
            try await Task.sleep(nanoseconds: widgetStreamTimeoutNanoseconds)
            return .timedOut
        }

        let result = try await group.next()
        group.cancelAll()
        return result
    }

    switch try #require(result, description) {
    case .element(let element):
        return element
    case .timedOut:
        let element: S.Element = try #require(nil as S.Element?, description)
        return element
    }
}
