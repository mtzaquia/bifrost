import Foundation
import Testing
@testable import SampleAppFeature

@Test("Request previews redact query and header values")
func requestPreviewIsStructural() throws {
    var request = URLRequest(
        url: try #require(URL(string: "https://user:secret@example.com/messages?token=sensitive"))
    )
    request.httpMethod = "POST"
    request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
    request.httpBody = Data(#"{"title":"Synthetic"}"#.utf8)

    let snapshot = RequestSnapshot(request)

    #expect(snapshot.method == "POST")
    #expect(snapshot.url == "https://example.com/messages?token=%3Credacted%3E")
    #expect(snapshot.url.contains("secret") == false)
    #expect(snapshot.headerNames == ["Authorization"])
    #expect(snapshot.bodyMetadata == "JSON · 21 bytes")
}

@Test("Guided response restart configures the recoverer first")
func responseRestartPresetIsGuided() {
    let options = LabConfiguration.options(for: .responseRestart)

    #expect(options.request.filter(\.isEnabled).map(\.kind) == [.metadata, .mock])
    #expect(options.response.filter(\.isEnabled).map(\.kind) == [.recover, .decorate, .audit])
}

@Test("The deterministic local mock cannot be disabled")
func localMockRemainsAvailable() {
    #expect(RequestInterceptorKind.mock.canDisable == false)
    #expect(RequestInterceptorKind.allCases.filter { $0.canDisable == false } == [.mock])
}

@MainActor
@Test("Lab controls toggle and reorder the active chain")
func labControlsChangeChain() {
    let model = PipelineLabModel()

    model.setRequestEnabled(.cache, enabled: true)
    model.moveRequest(.cache, offset: -1)
    model.moveRequest(.cache, offset: -1)

    #expect(model.activeRequestChain == [.cache, .metadata, .mock])

    model.setRequestEnabled(.metadata, enabled: false)
    model.setResponseEnabled(.audit, enabled: false)

    #expect(model.activeRequestChain == [.cache, .mock])
    #expect(model.activeResponseChain == [.decorate])
}

@Test("Step runtime pauses at a stage until advanced")
func stepRuntimeAdvancesDeterministically() async throws {
    let runtime = PipelineRuntime()
    let runID = await runtime.start(stepping: true)
    let baseline = await runtime.waitForUpdate(after: -1, id: runID)

    let checkpoint = Task {
        try await runtime.checkpoint(
            stage: .requestInterceptors,
            title: "Mutation",
            detail: ".continue",
            id: runID
        )
        try await runtime.completeCurrent(runID, detail: "continued")
    }

    let paused = await runtime.waitForUpdate(after: baseline.version, id: runID)
    #expect(paused.events.last?.state == .current)

    await runtime.advance(runID)
    try await checkpoint.value

    let completed = await runtime.waitForUpdate(after: paused.version, id: runID)
    #expect(completed.events.last?.state == .completed)
    #expect(completed.events.last?.detail == "continued")
}

@Test("Every guided success preset executes the real Bifrost pipeline", arguments: [
    LabPreset.mutation,
    .requestRestart,
    .requestReturn,
    .responseRestart,
    .responseReturn,
])
func guidedPresetExecutes(preset: LabPreset) async throws {
    let options = LabConfiguration.options(for: preset)
    let configuration = LabConfiguration(
        preset: preset,
        requestKinds: options.request.filter(\.isEnabled).map(\.kind),
        responseKinds: options.response.filter(\.isEnabled).map(\.kind)
    )
    let runtime = PipelineRuntime()
    let runID = await runtime.start(stepping: false)

    let response = try await PipelineLabAPI(
        configuration: configuration,
        runtime: runtime,
        runID: runID
    ).response(for: CreateLabMessage(title: "Aurora", priority: 2))
    try await runtime.finishSuccess(response, id: runID)

    let snapshot = await runtime.waitForUpdate(after: -1, id: runID)
    #expect(snapshot.isFinished)
    #expect(snapshot.events.last?.stage == .decoding)
    #expect(snapshot.events.last?.state == .completed)

    if preset == .requestRestart || preset == .responseRestart {
        #expect(snapshot.attempt == 2)
        #expect(snapshot.events.contains { $0.state == .restarted && $0.attempt == 1 })
        #expect(snapshot.events.filter { $0.state == .skipped }.allSatisfy { $0.attempt == 1 })
    }
}

@Test("Thrown failure bypasses the remaining pipeline")
func thrownFailureBypassesPipeline() async throws {
    let options = LabConfiguration.options(for: .thrownFailure)
    let configuration = LabConfiguration(
        preset: .thrownFailure,
        requestKinds: options.request.filter(\.isEnabled).map(\.kind),
        responseKinds: options.response.filter(\.isEnabled).map(\.kind)
    )
    let runtime = PipelineRuntime()
    let runID = await runtime.start(stepping: false)

    await #expect(throws: LabInjectedError.self) {
        _ = try await PipelineLabAPI(
            configuration: configuration,
            runtime: runtime,
            runID: runID
        ).response(for: CreateLabMessage(title: "Aurora", priority: 2))
    }

    try await runtime.markPipelineSkipped(runID, reason: "Injected failure")
    await runtime.finishFailure(LabInjectedError.requestInterceptor, id: runID)
    let snapshot = await runtime.waitForUpdate(after: -1, id: runID)

    #expect(snapshot.events.contains { $0.state == .failed })
    #expect(snapshot.events.filter { $0.state == .skipped }.count >= 3)
}
