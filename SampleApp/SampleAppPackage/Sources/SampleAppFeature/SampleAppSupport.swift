import Bifrost
import Foundation
import Observation

public enum SampleAppConfiguration {
    @MainActor
    public static func configure() {
        Bifrost.debug = .normal
    }
}

struct LabMessage: Codable, Equatable, Sendable {
    let id: Int
    let title: String
    let detail: String
}

struct CreateLabMessage: Requestable, Sendable {
    let title: String
    let priority: Int

    var path: String { "messages" }
    var method: HTTPMethod { .post }
    var headerFields: [String: String] { ["Content-Type": "application/json"] }

    typealias Response = LabMessage
}

enum LabPreset: String, CaseIterable, Identifiable, Sendable {
    case mutation
    case requestRestart
    case requestReturn
    case responseRestart
    case responseReturn
    case thrownFailure

    var id: Self { self }

    var title: String {
        switch self {
        case .mutation: "Mutate, validate, decode"
        case .requestRestart: "Restart before the mock"
        case .requestReturn: "Return cached content"
        case .responseRestart: "Recover after 401"
        case .responseReturn: "Return early from response"
        case .thrownFailure: "Throw from interception"
        }
    }

    var detail: String {
        switch self {
        case .mutation:
            "A request interceptor adds safe metadata, the local mock returns raw HTTP, and a response interceptor mutates the body before decoding."
        case .requestRestart:
            "The first attempt restarts before the mock. Bifrost rebuilds the URLRequest and reruns the request chain."
        case .requestReturn:
            "A cache interceptor returns raw HTTP immediately, skipping the remaining request chain and transport while preserving response processing."
        case .responseRestart:
            "The mock emits 401 once. A response interceptor refreshes sample-only state and restarts the full pipeline before validation."
        case .responseReturn:
            "A response interceptor replaces the raw response and returns, skipping the rest of the response chain but still validating and decoding."
        case .thrownFailure:
            "A request interceptor throws. Later request stages, response interception, validation, and decoding are bypassed."
        }
    }
}

enum RequestInterceptorKind: String, CaseIterable, Identifiable, Sendable {
    case metadata
    case restart
    case cache
    case failure
    case mock

    var id: Self { self }

    var title: String {
        switch self {
        case .metadata: "Add client metadata"
        case .restart: "Restart once"
        case .cache: "Return cache"
        case .failure: "Throw failure"
        case .mock: "Local HTTP mock"
        }
    }

    var result: String {
        switch self {
        case .metadata: "mutation + .continue"
        case .restart: ".restart on attempt 1"
        case .cache: ".return cached response"
        case .failure: "throw"
        case .mock: ".return fixture response"
        }
    }

    var canDisable: Bool { self != .mock }
}

enum ResponseInterceptorKind: String, CaseIterable, Identifiable, Sendable {
    case recover
    case decorate
    case returnEarly
    case audit
    case failure

    var id: Self { self }

    var title: String {
        switch self {
        case .recover: "Recover unauthorized"
        case .decorate: "Decorate body"
        case .returnEarly: "Return accepted response"
        case .audit: "Inspect metadata"
        case .failure: "Throw failure"
        }
    }

    var result: String {
        switch self {
        case .recover: ".restart on 401"
        case .decorate: "mutation + .continue"
        case .returnEarly: ".return replacement"
        case .audit: "inspect + .continue"
        case .failure: "throw"
        }
    }
}

struct RequestInterceptorOption: Identifiable, Sendable {
    let kind: RequestInterceptorKind
    var isEnabled: Bool
    var id: RequestInterceptorKind { kind }
}

struct ResponseInterceptorOption: Identifiable, Sendable {
    let kind: ResponseInterceptorKind
    var isEnabled: Bool
    var id: ResponseInterceptorKind { kind }
}

struct LabConfiguration: Sendable {
    let preset: LabPreset
    let requestKinds: [RequestInterceptorKind]
    let responseKinds: [ResponseInterceptorKind]

    static func options(for preset: LabPreset) -> (
        request: [RequestInterceptorOption],
        response: [ResponseInterceptorOption]
    ) {
        let requestOrder: [RequestInterceptorKind]
        let responseOrder: [ResponseInterceptorKind]
        let enabledRequest: Set<RequestInterceptorKind>
        let enabledResponse: Set<ResponseInterceptorKind>

        switch preset {
        case .mutation:
            requestOrder = [.metadata, .restart, .cache, .failure, .mock]
            responseOrder = [.decorate, .audit, .recover, .returnEarly, .failure]
            enabledRequest = [.metadata, .mock]
            enabledResponse = [.decorate, .audit]
        case .requestRestart:
            requestOrder = [.restart, .metadata, .cache, .failure, .mock]
            responseOrder = [.decorate, .audit, .recover, .returnEarly, .failure]
            enabledRequest = [.restart, .metadata, .mock]
            enabledResponse = [.decorate, .audit]
        case .requestReturn:
            requestOrder = [.cache, .metadata, .restart, .failure, .mock]
            responseOrder = [.decorate, .audit, .recover, .returnEarly, .failure]
            enabledRequest = [.cache, .metadata, .mock]
            enabledResponse = [.decorate, .audit]
        case .responseRestart:
            requestOrder = [.metadata, .restart, .cache, .failure, .mock]
            responseOrder = [.recover, .decorate, .audit, .returnEarly, .failure]
            enabledRequest = [.metadata, .mock]
            enabledResponse = [.recover, .decorate, .audit]
        case .responseReturn:
            requestOrder = [.metadata, .restart, .cache, .failure, .mock]
            responseOrder = [.returnEarly, .decorate, .audit, .recover, .failure]
            enabledRequest = [.metadata, .mock]
            enabledResponse = [.returnEarly, .decorate, .audit]
        case .thrownFailure:
            requestOrder = [.failure, .metadata, .restart, .cache, .mock]
            responseOrder = [.decorate, .audit, .recover, .returnEarly, .failure]
            enabledRequest = [.failure, .metadata, .mock]
            enabledResponse = [.decorate, .audit]
        }

        return (
            requestOrder.map { .init(kind: $0, isEnabled: enabledRequest.contains($0)) },
            responseOrder.map { .init(kind: $0, isEnabled: enabledResponse.contains($0)) }
        )
    }
}

enum PipelineStage: String, Sendable {
    case typedRequest = "Requestable"
    case builtRequest = "URLRequest"
    case requestInterceptors = "Request interceptors"
    case mock = "Transport / mock"
    case responseInterceptors = "Response interceptors"
    case validation = "Validation"
    case decoding = "Decoding"
}

enum PipelineEventState: Sendable {
    case current
    case completed
    case skipped
    case restarted
    case failed
}

struct RequestSnapshot: Equatable, Sendable {
    let method: String
    let url: String
    let headerNames: [String]
    let bodyMetadata: String

    init(_ request: URLRequest) {
        method = request.httpMethod ?? "GET"
        url = Self.redactedURL(request.url)
        headerNames = (request.allHTTPHeaderFields ?? [:]).keys.sorted()
        if let body = request.httpBody {
            bodyMetadata = "JSON · \(body.count) bytes"
        } else {
            bodyMetadata = "No body"
        }
    }

    private static func redactedURL(_ url: URL?) -> String {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<missing URL>"
        }
        components.user = nil
        components.password = nil
        components.queryItems = components.queryItems?.map {
            URLQueryItem(name: $0.name, value: "<redacted>")
        }
        return components.string ?? "<invalid URL>"
    }
}

struct ResponseSnapshot: Equatable, Sendable {
    let status: Int
    let headerNames: [String]
    let bodyMetadata: String

    init(_ response: InterceptedResponse) {
        status = response.statusCode
        headerNames = response.headerFields.keys.sorted()
        bodyMetadata = "JSON · \(response.body.count) bytes"
    }
}

struct PipelineEvent: Identifiable, Sendable {
    let id: UUID
    let stage: PipelineStage
    let title: String
    var detail: String
    let attempt: Int
    var state: PipelineEventState
    var requestBefore: RequestSnapshot?
    var requestAfter: RequestSnapshot?
    var responseBefore: ResponseSnapshot?
    var responseAfter: ResponseSnapshot?
}

enum ResponseSource: String, Sendable {
    case none = "Not reached"
    case localMock = "Local mock"
    case cache = "Request interceptor cache"
    case responseInterceptor = "Response interceptor"
}

struct RuntimeSnapshot: Sendable {
    let version: Int
    let events: [PipelineEvent]
    let attempt: Int
    let source: ResponseSource
    let isFinished: Bool
}

actor PipelineRuntime {
    private var runID = UUID()
    private var stepping = false
    private var cancelled = false
    private var attempt = 1
    private var source = ResponseSource.none
    private var events: [PipelineEvent] = []
    private var version = 0
    private var isFinished = false
    private var gate: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<RuntimeSnapshot, Never>] = []
    private var builtAttempts: Set<Int> = []

    func start(stepping: Bool) -> UUID {
        cancelCurrentRun()
        runID = UUID()
        self.stepping = stepping
        cancelled = false
        attempt = 1
        source = .none
        events = []
        version += 1
        isFinished = false
        builtAttempts = []
        notifyObservers()
        return runID
    }

    func cancel(_ id: UUID?) {
        guard id == nil || id == runID else { return }
        cancelCurrentRun()
    }

    func currentAttempt(for id: UUID) throws -> Int {
        try ensureActive(id)
        return attempt
    }

    func recordTypedRequest(_ id: UUID) throws {
        try ensureActive(id)
        append(
            stage: .typedRequest,
            title: "CreateLabMessage",
            detail: "Synthetic fixture: title Aurora, priority 2, response LabMessage",
            state: .completed
        )
    }

    func recordBuiltRequestIfNeeded(_ request: URLRequest, id: UUID) throws {
        try ensureActive(id)
        guard builtAttempts.insert(attempt).inserted else { return }
        let snapshot = RequestSnapshot(request)
        events.append(
            PipelineEvent(
                id: UUID(),
                stage: .builtRequest,
                title: attempt == 1 ? "Built URLRequest" : "Rebuilt URLRequest",
                detail: "Typed input encoded into transport shape; values remain redacted.",
                attempt: attempt,
                state: .completed,
                requestBefore: nil,
                requestAfter: snapshot,
                responseBefore: nil,
                responseAfter: nil
            )
        )
        changed()
    }

    func checkpoint(
        stage: PipelineStage,
        title: String,
        detail: String,
        request: RequestSnapshot? = nil,
        response: ResponseSnapshot? = nil,
        id: UUID
    ) async throws {
        try ensureActive(id)
        events.append(
            PipelineEvent(
                id: UUID(),
                stage: stage,
                title: title,
                detail: detail,
                attempt: attempt,
                state: .current,
                requestBefore: request,
                requestAfter: nil,
                responseBefore: response,
                responseAfter: nil
            )
        )
        changed()

        if stepping {
            await withCheckedContinuation { continuation in
                gate = continuation
            }
        }
        try ensureActive(id)
        try Task.checkCancellation()
    }

    func advance(_ id: UUID) {
        guard id == runID, cancelled == false else { return }
        let continuation = gate
        gate = nil
        continuation?.resume()
    }

    func completeCurrent(
        _ id: UUID,
        detail: String,
        state: PipelineEventState = .completed,
        requestAfter: RequestSnapshot? = nil,
        responseAfter: ResponseSnapshot? = nil,
        source: ResponseSource? = nil
    ) throws {
        try ensureActive(id)
        if let index = events.lastIndex(where: { $0.state == .current }) {
            events[index].detail = detail
            events[index].state = state
            events[index].requestAfter = requestAfter
            events[index].responseAfter = responseAfter
        }
        if let source { self.source = source }
        changed()
    }

    func skipRemaining(
        _ titles: [String],
        stage: PipelineStage,
        reason: String,
        id: UUID
    ) throws {
        try ensureActive(id)
        for title in titles {
            append(stage: stage, title: title, detail: reason, state: .skipped)
        }
    }

    func markPipelineSkipped(_ id: UUID, reason: String) throws {
        try ensureActive(id)
        append(stage: .responseInterceptors, title: "Response chain", detail: reason, state: .skipped)
        append(stage: .validation, title: "Status validation", detail: reason, state: .skipped)
        append(stage: .decoding, title: "Typed decoding", detail: reason, state: .skipped)
    }

    func restarted(
        _ id: UUID,
        detail: String,
        skippedTitles: [String],
        skippedStage: PipelineStage
    ) throws {
        try completeCurrent(id, detail: detail, state: .restarted)
        for title in skippedTitles {
            append(
                stage: skippedStage,
                title: title,
                detail: "Skipped on this attempt after .restart.",
                state: .skipped
            )
        }
        attempt += 1
        changed()
    }

    func finishSuccess(_ response: LabMessage, id: UUID) async throws {
        try await checkpoint(
            stage: .validation,
            title: "Status accepted",
            detail: "Inspect the final status accepted by API.response(for:).",
            id: id
        )
        try completeCurrent(
            id,
            detail: "Final HTTP status is within 200..<400."
        )
        try await checkpoint(
            stage: .decoding,
            title: "Decoded LabMessage",
            detail: "Inspect the response type decoded by API.response(for:).",
            id: id
        )
        try completeCurrent(
            id,
            detail: "#\(response.id) · \(response.title) · \(response.detail)"
        )
        isFinished = true
        changed()
    }

    func finishFailure(_ error: Error, id: UUID) {
        guard id == runID, cancelled == false else { return }
        if events.last?.state == .current {
            try? completeCurrent(id, detail: error.localizedDescription, state: .failed)
        }
        isFinished = true
        changed()
    }

    func waitForUpdate(after observedVersion: Int, id: UUID) async -> RuntimeSnapshot {
        if id != runID || version > observedVersion || isFinished {
            return snapshot()
        }
        return await withCheckedContinuation { continuation in
            observers.append(continuation)
        }
    }

    private func append(
        stage: PipelineStage,
        title: String,
        detail: String,
        state: PipelineEventState
    ) {
        events.append(
            PipelineEvent(
                id: UUID(),
                stage: stage,
                title: title,
                detail: detail,
                attempt: attempt,
                state: state,
                requestBefore: nil,
                requestAfter: nil,
                responseBefore: nil,
                responseAfter: nil
            )
        )
        changed()
    }

    private func ensureActive(_ id: UUID) throws {
        guard id == runID, cancelled == false else { throw CancellationError() }
    }

    private func cancelCurrentRun() {
        cancelled = true
        let continuation = gate
        gate = nil
        continuation?.resume()
        isFinished = true
        changed()
    }

    private func changed() {
        version += 1
        notifyObservers()
    }

    private func snapshot() -> RuntimeSnapshot {
        RuntimeSnapshot(
            version: version,
            events: events,
            attempt: attempt,
            source: source,
            isFinished: isFinished
        )
    }

    private func notifyObservers() {
        guard observers.isEmpty == false else { return }
        let snapshot = snapshot()
        let continuations = observers
        observers = []
        continuations.forEach { $0.resume(returning: snapshot) }
    }
}

enum LabInjectedError: LocalizedError {
    case requestInterceptor
    case responseInterceptor

    var errorDescription: String? {
        switch self {
        case .requestInterceptor: "The sample request interceptor threw an injected failure."
        case .responseInterceptor: "The sample response interceptor threw an injected failure."
        }
    }
}

struct LabRequestInterceptor: RequestInterceptor {
    let kind: RequestInterceptorKind
    let laterTitles: [String]
    let configuration: LabConfiguration
    let runtime: PipelineRuntime
    let runID: UUID

    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request: Requestable {
        try await runtime.recordBuiltRequestIfNeeded(context.urlRequest, id: runID)
        let before = RequestSnapshot(context.urlRequest)
        try await runtime.checkpoint(
            stage: kind == .mock || kind == .cache ? .mock : .requestInterceptors,
            title: kind.title,
            detail: kind.result,
            request: before,
            id: runID
        )

        switch kind {
        case .metadata:
            context.urlRequest.setValue("<sample-token>", forHTTPHeaderField: "Authorization")
            context.urlRequest.setValue("pipeline-lab", forHTTPHeaderField: "X-Bifrost-Client")
            try await runtime.completeCurrent(
                runID,
                detail: "Added Authorization and X-Bifrost-Client; values stay redacted.",
                requestAfter: RequestSnapshot(context.urlRequest)
            )
            return .continue

        case .restart:
            if try await runtime.currentAttempt(for: runID) == 1 {
                try await runtime.restarted(
                    runID,
                    detail: "Returned .restart; this attempt stops before the mock.",
                    skippedTitles: laterTitles,
                    skippedStage: .requestInterceptors
                )
                return .restart
            }
            try await runtime.completeCurrent(runID, detail: "Already restarted once; returned .continue.")
            return .continue

        case .cache:
            let response = try makeResponse(
                for: context.urlRequest,
                status: 200,
                message: LabMessage(id: 7, title: "Cached Aurora", detail: "Decoded after request .return"),
                header: "X-Bifrost-Cache"
            )
            try await runtime.completeCurrent(
                runID,
                detail: "Returned cached raw HTTP; later request interceptors and transport are skipped.",
                responseAfter: ResponseSnapshot(response),
                source: .cache
            )
            try await runtime.skipRemaining(
                laterTitles,
                stage: .requestInterceptors,
                reason: "Skipped after request .return.",
                id: runID
            )
            return .return(response)

        case .failure:
            try await runtime.completeCurrent(
                runID,
                detail: LabInjectedError.requestInterceptor.localizedDescription,
                state: .failed
            )
            try await runtime.skipRemaining(
                laterTitles,
                stage: .requestInterceptors,
                reason: "Bypassed after the thrown error.",
                id: runID
            )
            throw LabInjectedError.requestInterceptor

        case .mock:
            let currentAttempt = try await runtime.currentAttempt(for: runID)
            let status = configuration.preset == .responseRestart && currentAttempt == 1 ? 401 : 200
            let message = status == 401
                ? LabMessage(id: 0, title: "Unauthorized", detail: "Sample credential expired")
                : LabMessage(id: 42, title: "Aurora", detail: "Decoded from deterministic raw HTTP")
            let response = try makeResponse(
                for: context.urlRequest,
                status: status,
                message: message,
                header: "X-Bifrost-Fixture"
            )
            try await runtime.completeCurrent(
                runID,
                detail: "Returned local HTTP \(status); no network request was made.",
                responseAfter: ResponseSnapshot(response),
                source: .localMock
            )
            try await runtime.skipRemaining(
                laterTitles,
                stage: .requestInterceptors,
                reason: "Skipped after the local mock returned.",
                id: runID
            )
            return .return(response)
        }
    }
}

struct LabResponseInterceptor: ResponseInterceptor {
    let kind: ResponseInterceptorKind
    let laterTitles: [String]
    let runtime: PipelineRuntime
    let runID: UUID

    func intercept(
        _ response: inout InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        let before = ResponseSnapshot(response)
        try await runtime.checkpoint(
            stage: .responseInterceptors,
            title: kind.title,
            detail: kind.result,
            response: before,
            id: runID
        )

        switch kind {
        case .recover:
            if response.statusCode == 401 {
                try await runtime.restarted(
                    runID,
                    detail: "Observed 401, refreshed sample state, and returned .restart.",
                    skippedTitles: laterTitles,
                    skippedStage: .responseInterceptors
                )
                return .restart
            }
            try await runtime.completeCurrent(runID, detail: "Status was \(response.statusCode); returned .continue.")
            return .continue

        case .decorate:
            var message = try JSONDecoder().decode(LabMessage.self, from: response.body)
            message = LabMessage(id: message.id, title: message.title, detail: message.detail + " → decorated")
            response.body = try JSONEncoder().encode(message)
            response.httpResponse = try replacingHeaders(
                in: response.httpResponse,
                with: response.headerFields.merging(["X-Bifrost-Decorated": "true"]) { _, new in new }
            )
            try await runtime.completeCurrent(
                runID,
                detail: "Mutated body metadata and added X-Bifrost-Decorated, then continued.",
                responseAfter: ResponseSnapshot(response)
            )
            return .continue

        case .returnEarly:
            let replacement = try makeResponse(
                for: URLRequest(url: response.httpResponse.url ?? URL(string: "https://sample.bifrost.dev")!),
                status: 202,
                message: LabMessage(id: 202, title: "Accepted early", detail: "Decoded after response .return"),
                header: "X-Bifrost-Response-Return"
            )
            try await runtime.completeCurrent(
                runID,
                detail: "Returned replacement HTTP 202; remaining response interceptors are skipped.",
                responseAfter: ResponseSnapshot(replacement),
                source: .responseInterceptor
            )
            try await runtime.skipRemaining(
                laterTitles,
                stage: .responseInterceptors,
                reason: "Skipped after response .return.",
                id: runID
            )
            return .return(replacement)

        case .audit:
            try await runtime.completeCurrent(
                runID,
                detail: "Inspected status, header names, and body byte count; returned .continue.",
                responseAfter: before
            )
            return .continue

        case .failure:
            try await runtime.completeCurrent(
                runID,
                detail: LabInjectedError.responseInterceptor.localizedDescription,
                state: .failed
            )
            try await runtime.skipRemaining(
                laterTitles,
                stage: .responseInterceptors,
                reason: "Bypassed after the thrown error.",
                id: runID
            )
            throw LabInjectedError.responseInterceptor
        }
    }
}

struct PipelineLabAPI: API {
    let baseURL = URL(string: "https://sample.bifrost.dev/v1?client=sample")!
    let requestInterceptors: [any RequestInterceptor]
    let responseInterceptors: [any ResponseInterceptor]

    func queryParameters() -> [URLQueryItem] {
        [URLQueryItem(name: "locale", value: "en")]
    }

    init(configuration: LabConfiguration, runtime: PipelineRuntime, runID: UUID) {
        requestInterceptors = configuration.requestKinds.enumerated().map { index, kind in
            LabRequestInterceptor(
                kind: kind,
                laterTitles: configuration.requestKinds.dropFirst(index + 1).map(\.title),
                configuration: configuration,
                runtime: runtime,
                runID: runID
            )
        }
        responseInterceptors = configuration.responseKinds.enumerated().map { index, kind in
            LabResponseInterceptor(
                kind: kind,
                laterTitles: configuration.responseKinds.dropFirst(index + 1).map(\.title),
                runtime: runtime,
                runID: runID
            )
        }
    }
}

private func makeResponse(
    for request: URLRequest,
    status: Int,
    message: LabMessage,
    header: String
) throws -> InterceptedResponse {
    guard let url = request.url,
          let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", header: "true"]
          ) else {
        throw URLError(.badServerResponse)
    }
    return InterceptedResponse(body: try JSONEncoder().encode(message), httpResponse: response)
}

private func replacingHeaders(
    in response: HTTPURLResponse,
    with headers: [String: String]
) throws -> HTTPURLResponse {
    guard let url = response.url,
          let replacement = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
          ) else {
        throw URLError(.badServerResponse)
    }
    return replacement
}

enum LabRunState: Equatable {
    case idle
    case stepping
    case running
    case succeeded
    case failed(String)
}

@MainActor
@Observable
final class PipelineLabModel {
    private let runtime = PipelineRuntime()
    private var runTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var runID: UUID?

    var preset = LabPreset.mutation
    var requestOptions: [RequestInterceptorOption]
    var responseOptions: [ResponseInterceptorOption]
    private(set) var events: [PipelineEvent] = []
    private(set) var attempt = 1
    private(set) var responseSource = ResponseSource.none
    private(set) var runState = LabRunState.idle

    init() {
        let options = LabConfiguration.options(for: .mutation)
        requestOptions = options.request
        responseOptions = options.response
    }

    var activeRequestChain: [RequestInterceptorKind] {
        requestOptions.filter(\.isEnabled).map(\.kind)
    }

    var activeResponseChain: [ResponseInterceptorKind] {
        responseOptions.filter(\.isEnabled).map(\.kind)
    }

    var currentEvent: PipelineEvent? {
        events.last(where: { $0.state == .current })
    }

    var nextAction: String {
        switch runState {
        case .idle: "Run the full pipeline or start step-through mode"
        case .stepping: currentEvent.map { "Continue from \($0.title)" } ?? "Wait for the next stage"
        case .running: "The full pipeline is running"
        case .succeeded: "Reset or replay the experiment"
        case .failed: "Inspect the bypassed stages, then reset"
        }
    }

    var isActive: Bool {
        runState == .stepping || runState == .running
    }

    func selectPreset(_ preset: LabPreset) {
        reset()
        self.preset = preset
        let options = LabConfiguration.options(for: preset)
        requestOptions = options.request
        responseOptions = options.response
    }

    func setRequestEnabled(_ kind: RequestInterceptorKind, enabled: Bool) {
        guard let index = requestOptions.firstIndex(where: { $0.kind == kind }), kind.canDisable else { return }
        requestOptions[index].isEnabled = enabled
        resetResults()
    }

    func setResponseEnabled(_ kind: ResponseInterceptorKind, enabled: Bool) {
        guard let index = responseOptions.firstIndex(where: { $0.kind == kind }) else { return }
        responseOptions[index].isEnabled = enabled
        resetResults()
    }

    func moveRequest(_ kind: RequestInterceptorKind, offset: Int) {
        guard let source = requestOptions.firstIndex(where: { $0.kind == kind }) else { return }
        let destination = source + offset
        guard requestOptions.indices.contains(destination) else { return }
        requestOptions.swapAt(source, destination)
        resetResults()
    }

    func moveResponse(_ kind: ResponseInterceptorKind, offset: Int) {
        guard let source = responseOptions.firstIndex(where: { $0.kind == kind }) else { return }
        let destination = source + offset
        guard responseOptions.indices.contains(destination) else { return }
        responseOptions.swapAt(source, destination)
        resetResults()
    }

    func runFull() {
        begin(stepping: false)
    }

    func step() {
        if runState == .idle || runState == .succeeded || isFailure {
            begin(stepping: true)
        } else if runState == .stepping, let runID {
            Task { await runtime.advance(runID) }
        }
    }

    func reset() {
        runTask?.cancel()
        observationTask?.cancel()
        let previousID = runID
        runID = nil
        Task { await runtime.cancel(previousID) }
        resetResults()
    }

    private var isFailure: Bool {
        if case .failed = runState { true } else { false }
    }

    private func resetResults() {
        events = []
        attempt = 1
        responseSource = .none
        runState = .idle
    }

    private func begin(stepping: Bool) {
        reset()
        let configuration = LabConfiguration(
            preset: preset,
            requestKinds: activeRequestChain,
            responseKinds: activeResponseChain
        )
        runState = stepping ? .stepping : .running

        runTask = Task { [weak self] in
            guard let self else { return }
            let id = await runtime.start(stepping: stepping)
            guard Task.isCancelled == false else { return }
            runID = id
            observe(id)

            do {
                try await runtime.recordTypedRequest(id)
                let response = try await PipelineLabAPI(
                    configuration: configuration,
                    runtime: runtime,
                    runID: id
                ).response(for: CreateLabMessage(title: "Aurora", priority: 2))
                try await runtime.finishSuccess(response, id: id)
                runState = .succeeded
            } catch is CancellationError {
                return
            } catch {
                try? await runtime.markPipelineSkipped(id, reason: "Bypassed after \(error.localizedDescription)")
                await runtime.finishFailure(error, id: id)
                runState = .failed(error.localizedDescription)
            }
        }
    }

    private func observe(_ id: UUID) {
        observationTask = Task { [weak self] in
            guard let self else { return }
            var version = -1
            while Task.isCancelled == false {
                let snapshot = await runtime.waitForUpdate(after: version, id: id)
                guard id == runID else { return }
                version = snapshot.version
                events = snapshot.events
                attempt = snapshot.attempt
                responseSource = snapshot.source
                if snapshot.isFinished { return }
            }
        }
    }
}
