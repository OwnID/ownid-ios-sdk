import Foundation

internal final class EventsAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest
    private static let dateFormatterLock = NSLock()
    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    internal init(
        apiBaseURL: URL,
        coder: any JSONCoder,
        userJourney: UserJourneySummary,
        traceParent: String
    ) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("event/journey"))

        let body = try coder.encodeToString(EventsAPICall.map(userJourney, traceParent: traceParent))
        request.setBody(body)
        request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<Void, EventsFailure> {
        guard successResponse.code == 204 else { return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail())) }
        return .success(())
    }

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> EventsFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadRequestErrorResponse.self,
                unexpected: EventsFailure.unexpected
            ) { response in
                response.toFailure(
                    invalidArgument: { .badRequest(errorCode: $0, message: $1) },
                    unknown: { .badRequest(errorCode: $0, message: $1) }
                )
            }

        default:
            return failResponse.toUnexpectedFailure(EventsFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> EventsFailure {
        failResponse.toUnexpectedFailure(EventsFailure.unexpected)
    }

    private static func map(_ journey: UserJourneySummary, traceParent: String) throws -> InternalUserJourneySummary {
        let flows: [InternalFlow] = journey.eventInfo.flows.map { flow in
            let steps: [InternalStep] = flow.steps.map { step in
                InternalStep(
                    operationType: step.operationType.toInternalModel(),
                    name: step.name,
                    status: {
                        switch step.status {
                        case .aborted: .aborted
                        case .inProgress: .inProgress
                        case .completed: .completed
                        case .failed: .failed
                        }
                    }(),
                    startedAt: Self.formatDate(step.startedAt),
                    completedAt: step.completedAt.map(Self.formatDate(_:)),
                    errors: step.errors?.map { InternalClientError(errorCode: $0.errorCode, source: $0.source, message: $0.message) },
                    insights: step.insights.map {
                        InternalStepInsights(duration: $0.duration, retries: $0.retries, clicksCount: $0.clicksCount)
                    }
                )
            }

            return InternalFlow(
                id: flow.id,
                name: flow.name,
                source: {
                    switch flow.source {
                    case .widgetButton: .widgetButton
                    case .returningUserPrompt: .returningUserPrompt
                    case .recoveryPrompt: .recoveryPrompt
                    case .enrollPrompt: .enrollPrompt
                    case .elite: .elite
                    case .agentAuthorizing: .agentAuthorizing
                    case .deferred: .deferred
                    case .explicit: .explicit
                    case .implicit: .implicit
                    }
                }(),
                status: {
                    switch flow.status {
                    case .aborted: .aborted
                    case .inProgress: .inProgress
                    case .completed: .completed
                    case .switched: .switched
                    case .failed: .failed
                    }
                }(),
                startedAt: Self.formatDate(flow.startedAt),
                completedAt: flow.completedAt.map(Self.formatDate(_:)),
                errors: flow.errors?.map { InternalClientError(errorCode: $0.errorCode, source: $0.source, message: $0.message) },
                switchedToFlow: flow.switchedToFlow,
                insights: flow.insights.map { insight in
                    InternalFlowInsights(
                        duration: insight.duration,
                        errorRate: insight.errorRate,
                        retries: insight.retries,
                        clicksCount: insight.clicksCount,
                        authMethod: {
                            switch insight.authMethod {
                            case .otp: return .otp
                            case .passkey: return .passkey
                            case .magicLink: return .magicLink
                            case .password: return .password
                            case .deferred: return .deferred
                            case .immediate: return .immediate
                            case .socialGoogle: return .socialGoogle
                            case .socialApple: return .socialApple
                            case .facekey: return .facekey
                            case .unknown: return .unknown
                            case nil: return nil
                            }
                        }(),
                        loggedIn: insight.loggedIn,
                        registered: insight.registered
                    )
                },
                steps: steps
            )
        }

        return InternalUserJourneySummary(
            id: journey.id,
            traceparent: traceParent,
            reporter: InternalReporter(
                service: {
                    switch journey.reporter.service {
                    case .webSdk: .webSdk
                    case .androidSdk: .androidSdk
                    case .iosSdk: .iosSdk
                    }
                }(),
                version: journey.reporter.version,
                origin: journey.reporter.origin,
                referer: journey.reporter.referer
            ),
            eventInfo: InternalEventInfo(type: .journeySummary, flows: flows),
            deviceInfo: InternalClientDeviceInfo(
                isPlatformAuthenticatorAvailable: journey.deviceInfo.isPlatformAuthenticatorAvailable,
                isWebView: journey.deviceInfo.isWebView,
                isMobileNative: journey.deviceInfo.isMobileNative
            ),
            userInfo: journey.userInfo.map { info in
                InternalUserInfo(
                    loginId: InternalLoginId(id: info.loginId.id, type: info.loginId.type.toInternalModel()),
                    returningUser: info.returningUser,
                    lastAuthMethod: {
                        switch info.lastAuthMethod {
                        case .otp: return .otp
                        case .passkey: return .passkey
                        case .magicLink: return .magicLink
                        case .password: return .password
                        case .deferred: return .deferred
                        case .immediate: return .immediate
                        case .socialGoogle: return .socialGoogle
                        case .socialApple: return .socialApple
                        case .facekey: return .facekey
                        case .unknown: return .unknown
                        case nil: return nil
                        }
                    }()
                )
            }
        )
    }

    private static func formatDate(_ date: Date) -> String {
        dateFormatterLock.lock()
        defer { dateFormatterLock.unlock() }
        return dateFormatter.string(from: date)
    }
}
