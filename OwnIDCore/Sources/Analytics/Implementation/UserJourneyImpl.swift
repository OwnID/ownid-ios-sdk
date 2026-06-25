import Foundation

/// Default `UserJourney` collector for an SDK instance.
///
/// The collector accepts telemetry updates for one active journey and schedules a single summary submission when the
/// active flow completes. Completion resets retained journey data before the next flow starts. Submission failures are
/// logged and do not affect the SDK flow that already produced the analytics outcome.
internal actor UserJourneyImpl: UserJourney {
    private let eventsApi: any EventsAPI
    private let localInfo: any LocalInfo
    private let userRepository: (any UserRepository)?
    nonisolated private let taskScope: TaskScope
    private let logger: OwnIDLogRouter?

    internal init(
        eventsApi: any EventsAPI,
        localInfo: any LocalInfo,
        userRepository: (any UserRepository)?,
        taskScope: TaskScope,
        logger: OwnIDLogRouter?
    ) {
        self.eventsApi = eventsApi
        self.localInfo = localInfo
        self.userRepository = userRepository
        self.taskScope = taskScope
        self.logger = logger
        self.journeyId = UUID().uuidString
        self.referer = "ios-app://\(localInfo.bundleID)"
        self.submitted = false
        self.userInfo = []
        self.flows = []
        self.currentFlow = nil
        self.traceParent = nil
    }

    private struct StepData {
        let operationType: OperationType
        let name: String?
        let startedAtWall: Date
        let startedAtUptime: TimeInterval
        var clicks: Int = 0
        var status: Step.Status = .inProgress
        var completedAtWall: Date? = nil
        var completedAtUptime: TimeInterval? = nil
        var errors: [ClientError]? = nil
    }

    private struct FlowData {
        let id: String
        var name: String?
        var source: FlowInfo.Source
        let startedAtWall: Date
        let startedAtUptime: TimeInterval
        var completedAtWall: Date? = nil
        var completedAtUptime: TimeInterval? = nil
        var status: FlowInfo.Status = .inProgress
        var switchedToFlow: String? = nil
        var steps: [OperationID: StepData] = [:]
        var errors: [ClientError]? = nil
        var insightsAuthMethod: AuthMethod? = nil
        var insightsLoggedIn: Bool? = nil
        var insightsRegistered: Bool? = nil
    }

    private var journeyId: String = UUID().uuidString
    private var referer: String? = nil
    private var submitted: Bool = false
    private var userInfo: [UserJourneySummary.UserInfo] = []
    private var flows: [FlowData] = []
    private var currentFlow: FlowData? = nil
    private var traceParent: String? = nil

    private func now() -> (Date, TimeInterval) { (Date(), ProcessInfo.processInfo.systemUptime) }

    private func resetJourney() {
        journeyId = UUID().uuidString
        referer = "ios-app://\(localInfo.bundleID)"
        submitted = false
        userInfo = []
        flows = []
        currentFlow = nil
        traceParent = nil
    }

    func startFlow(name: String?, source: FlowInfo.Source, traceParent: String?) async {
        if submitted { resetJourney() }
        if let traceParent { self.traceParent = traceParent }

        if var cf = currentFlow {
            cf.name = name ?? cf.name
            cf.source = source
            currentFlow = cf
            return
        }

        let id = UUID().uuidString
        let (w, u) = now()
        currentFlow = FlowData(id: id, name: name, source: source, startedAtWall: w, startedAtUptime: u)
        flows.append(currentFlow!)
    }

    func switchToFlow(flowID: String?, name: String?, source: FlowInfo.Source) async {
        if submitted {
            logger?.logW(source: self, prefix: #function, message: "Ignored switchToFlow on submitted journey")
            return
        }
        let newFlowID = flowID ?? UUID().uuidString
        if var cf = currentFlow {
            cf.status = .switched
            cf.switchedToFlow = newFlowID
            let (w, u) = now()
            cf.completedAtWall = w
            cf.completedAtUptime = u
            cf.steps = cf.steps.mapValues { step in
                var s = step
                if s.status == .inProgress {
                    s.status = .aborted
                    s.completedAtWall = w
                    s.completedAtUptime = u
                }
                return s
            }
            if let idx = flows.firstIndex(where: { $0.id == cf.id }) { flows[idx] = cf }
        }
        let (w, u) = now()
        let nf = FlowData(id: newFlowID, name: name, source: source, startedAtWall: w, startedAtUptime: u)
        flows.append(nf)
        currentFlow = nf
    }

    func setUserInfo(_ loginID: LoginID) async {
        if userInfo.contains(where: { $0.loginId.id == loginID.id }) { return }

        userInfo.append(.init(loginId: loginID, returningUser: false, lastAuthMethod: nil))
        do {
            if let last = try await self.userRepository?.lastUser(), last.loginID.id == loginID.id {
                let method = last.authMethod
                self.updateUserInfo(loginID: loginID, returning: true, lastAuthMethod: method)
            }
        } catch {
            // ignore enrichment errors
        }
    }

    private func updateUserInfo(loginID: LoginID, returning: Bool, lastAuthMethod: AuthMethod?) {
        if let idx = userInfo.firstIndex(where: { $0.loginId.id == loginID.id }) {
            userInfo[idx] = .init(loginId: loginID, returningUser: returning, lastAuthMethod: lastAuthMethod)
        }
    }

    func setReferer(_ referer: String) async {
        self.referer = referer
    }

    func startOperation(operationID: OperationID) async {
        guard var cf = currentFlow else {
            logger?.logW(source: self, prefix: #function, message: "No active flow for operation: \(operationID)")
            return
        }
        if cf.steps[operationID] != nil {
            logger?.logW(source: self, prefix: #function, message: "Duplicate startOperation: \(operationID)")
        }
        let (w, u) = now()
        cf.steps[operationID] = StepData(operationType: operationID.type, name: nil, startedAtWall: w, startedAtUptime: u)
        if let idx = flows.firstIndex(where: { $0.id == cf.id }) {
            flows[idx] = cf
            currentFlow = cf
        }
    }

    func addOperationClick(operationID: OperationID) async {
        guard var cf = currentFlow, var step = cf.steps[operationID] else {
            logger?.logW(source: self, prefix: #function, message: "Unknown operation: \(operationID)")
            return
        }
        step.clicks += 1
        cf.steps[operationID] = step
        if let idx = flows.firstIndex(where: { $0.id == cf.id }) {
            flows[idx] = cf
            currentFlow = cf
        }
    }

    func completeOperation(operationID: OperationID, errorCode: ErrorCode?, source: String?, message: String?) async {
        guard var cf = currentFlow, var step = cf.steps[operationID] else {
            logger?.logW(source: self, prefix: #function, message: "Unknown operation: \(operationID)")
            return
        }
        step.status = {
            switch errorCode {
            case nil: return .completed
            case .some(.aborted): return .aborted
            default: return .failed
            }
        }()
        let (w, u) = now()
        step.completedAtWall = w
        step.completedAtUptime = u
        if let code = errorCode {
            let clientErr = ClientError(errorCode: code.value, source: source, message: message)
            if step.errors == nil { step.errors = [clientErr] } else { step.errors!.append(clientErr) }
        }
        cf.steps[operationID] = step
        if let idx = flows.firstIndex(where: { $0.id == cf.id }) {
            flows[idx] = cf
            currentFlow = cf
        }
    }

    nonisolated func completeFlow(_ outcome: UserJourneyOutcome) {
        _ = taskScope.spawn { [weak self] in
            guard let self else { return }
            await self.completeFlowInternal(outcome)
        }
    }

    private func completeFlowInternal(_ outcome: UserJourneyOutcome) async {
        if submitted {
            logger?.logW(source: self, prefix: #function, message: "Duplicate completeFlow ignored")
            return
        }

        if var flow = currentFlow {
            flow.status = {
                switch outcome {
                case .error(let errorCode, _, _): return errorCode == .aborted ? .aborted : .failed
                case .completed, .loggedIn, .registered: return .completed
                }
            }()
            let (w, u) = now()
            flow.completedAtWall = w
            flow.completedAtUptime = u
            flow.insightsAuthMethod = {
                switch outcome {
                case .loggedIn(let m): return m
                case .registered(let m?), .completed(let m?): return m
                default: return nil
                }
            }()
            flow.insightsLoggedIn = { if case .loggedIn = outcome { return true } else { return nil } }()
            flow.insightsRegistered = { if case .registered = outcome { return true } else { return nil } }()
            if case .error(let errorCode, let source, let msg) = outcome {
                let err = ClientError(errorCode: errorCode.value, source: source, message: msg)
                if flow.errors == nil { flow.errors = [err] } else { flow.errors!.append(err) }
            }
            if let idx = flows.firstIndex(where: { $0.id == flow.id }) {
                flows[idx] = flow
                currentFlow = flow
            }
        }

        let flowSummaries: [FlowInfo] = flows.map { flow in
            let stepSummaries: [Step] = flow.steps.values
                .sorted { $0.startedAtWall < $1.startedAtWall }
                .map { step in
                    let dur = (step.completedAtUptime ?? step.startedAtUptime) - step.startedAtUptime
                    let durMs = step.completedAtUptime == nil ? nil : Int64(dur * 1000)
                    let clicks = step.clicks > 0 ? step.clicks : 0
                    let step = Step(
                        operationType: step.operationType,
                        name: step.name,
                        status: step.status,
                        startedAt: step.startedAtWall,
                        completedAt: step.completedAtWall,
                        errors: step.errors,
                        insights: Step.Insights(duration: durMs, retries: nil, clicksCount: clicks > 0 ? clicks : nil)
                    )
                    return step
                }
            let flowDur = (flow.completedAtUptime ?? flow.startedAtUptime) - flow.startedAtUptime
            let flowDurMs = flow.completedAtUptime == nil ? nil : Int64(flowDur * 1000)
            let insights = FlowInfo.Insights(
                duration: flowDurMs,
                errorRate: nil,
                retries: nil,
                clicksCount: flow.steps.values.reduce(0) { $0 + $1.clicks },
                authMethod: flow.insightsAuthMethod,
                loggedIn: flow.insightsLoggedIn,
                registered: flow.insightsRegistered
            )
            return FlowInfo(
                id: flow.id,
                name: flow.name,
                source: flow.source,
                status: flow.status,
                startedAt: flow.startedAtWall,
                completedAt: flow.completedAtWall,
                errors: flow.errors,
                switchedToFlow: flow.switchedToFlow,
                insights: insights,
                steps: stepSummaries
            )
        }

        let summary = UserJourneySummary(
            id: journeyId,
            reporter: .init(
                service: .iosSdk,
                origin: localInfo.bundleID,
                referer: referer ?? "ios-app://\(localInfo.bundleID)",
                version: localInfo.appVersion
            ),
            eventInfo: .init(type: .journeySummary, flows: flowSummaries),
            deviceInfo: .init(
                isPlatformAuthenticatorAvailable: localInfo.isSystemFidoCapable,
                isWebView: false,
                isMobileNative: true
            ),
            userInfo: userInfo
        )

        submitted = true
        let flowCount = self.flows.count

        _ = taskScope.spawn { [eventsApi, logger, flowCount, traceParent = self.traceParent] in
            await eventsApi.start(params: EventsAPIParams(userJourney: summary, traceParent: traceParent))
                .onSuccess { _ in
                    logger?.logD(source: self, prefix: #function, message: "EventsAPI success for journey with \(flowCount) flow(s)")
                }
                .onError { err in
                    logger?.logW(source: self, prefix: #function, message: "EventsAPI failure: \(err.message)")
                }
                .onCanceled {
                    logger?.logD(source: self, prefix: #function, message: "EventsAPI canceled for journey with \(flowCount) flow(s)")
                }
        }
    }

    static func create(resolver: any DIContainerResolver) -> any UserJourney {
        do {
            return UserJourneyImpl(
                eventsApi: try resolver.getOrThrow(type: (any EventsAPI).self),
                localInfo: try resolver.getOrThrow(type: (any LocalInfo).self),
                userRepository: resolver.getOrNil(type: (any UserRepository).self),
                taskScope: try resolver.getOrThrow(type: TaskScope.self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self)
            )
        } catch {
            return MissingUserJourney()
        }
    }
}

private actor MissingUserJourney: UserJourney {
    func startFlow(name: String?, source: FlowInfo.Source, traceParent: String?) async {}
    func switchToFlow(flowID: String?, name: String?, source: FlowInfo.Source) async {}
    func setUserInfo(_ loginID: LoginID) async {}
    func setReferer(_ referer: String) async {}
    func startOperation(operationID: OperationID) async {}
    func addOperationClick(operationID: OperationID) async {}
    func completeOperation(operationID: OperationID, errorCode: ErrorCode?, source: String?, message: String?) async {}
    nonisolated func completeFlow(_ outcome: UserJourneyOutcome) {}
}
