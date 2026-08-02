import SwiftUI

public struct ContentView: View {
    @State private var model = PipelineLabModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            PipelineLabView(model: model)
        }
    }
}

private struct PipelineLabView: View {
    @Bindable var model: PipelineLabModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("See typed HTTP as a pipeline", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.title2.bold())
                    Text("Change an ordered interceptor chain, run Bifrost's real API.response(for:) path, and inspect exactly what completed, restarted, or was skipped.")
                        .foregroundStyle(.secondary)
                    PipelineMap(currentStage: model.currentEvent?.stage)
                }
                .padding(.vertical, 8)
            }

            Section("Experiment") {
                Picker("Guided preset", selection: presetBinding) {
                    ForEach(LabPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .disabled(model.isActive)

                Text(model.preset.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LabeledContent("Typed request") {
                    Text("CreateLabMessage")
                        .font(.subheadline.monospaced())
                }
                LabeledContent("Fixture input") {
                    Text("Aurora · priority 2")
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Expected type") {
                    Text("LabMessage")
                        .font(.subheadline.monospaced())
                }
            }

            interceptorSection
            controlsSection
            statusSection

            if model.events.isEmpty == false {
                Section("Pipeline trace") {
                    ForEach(model.events) { event in
                        PipelineEventRow(event: event)
                    }
                }
            }

            if latestRequestSnapshots != nil || latestResponseSnapshots != nil {
                Section("Safe before / after") {
                    if let snapshots = latestRequestSnapshots,
                       let before = snapshots.requestBefore ?? snapshots.requestAfter,
                       let after = snapshots.requestAfter {
                        RequestComparison(before: before, after: after)
                    }
                    if let snapshots = latestResponseSnapshots,
                       let before = snapshots.responseBefore ?? snapshots.responseAfter,
                       let after = snapshots.responseAfter {
                        ResponseComparison(before: before, after: after)
                    }
                }
            }

            if let finalEvent {
                Section("Final decoded result") {
                    Label(finalEvent.title, systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(finalEvent.detail)
                        .foregroundStyle(.secondary)
                }
            }

            if case .failed(let message) = model.runState {
                Section("Final error") {
                    Label("Pipeline stopped", systemImage: "xmark.octagon.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Bifrost Pipeline Lab")
    }

    private var presetBinding: Binding<LabPreset> {
        Binding(
            get: { model.preset },
            set: { model.selectPreset($0) }
        )
    }

    private var latestRequestSnapshots: PipelineEvent? {
        model.events.last(where: {
            $0.requestBefore != nil || $0.requestAfter != nil
        })
    }

    private var latestResponseSnapshots: PipelineEvent? {
        model.events.last(where: {
            $0.responseBefore != nil || $0.responseAfter != nil
        })
    }

    private var finalEvent: PipelineEvent? {
        model.events.last { event in
            event.stage == .decoding && event.state == .completed
        }
    }

    private var interceptorSection: some View {
        Section {
            DisclosureGroup {
                VStack(spacing: 12) {
                    ForEach(Array(model.requestOptions.enumerated()), id: \.element.id) { index, option in
                        InterceptorOptionRow(
                            title: option.kind.title,
                            result: option.kind.result,
                            isEnabled: Binding(
                                get: { model.requestOptions[index].isEnabled },
                                set: { model.setRequestEnabled(option.kind, enabled: $0) }
                            ),
                            canDisable: option.kind.canDisable,
                            canMoveUp: index > 0,
                            canMoveDown: index < model.requestOptions.count - 1,
                            moveUp: { model.moveRequest(option.kind, offset: -1) },
                            moveDown: { model.moveRequest(option.kind, offset: 1) }
                        )
                    }
                }
                .padding(.top, 8)
            } label: {
                ChainSummary(
                    title: "Request chain",
                    names: model.activeRequestChain.map(\.title),
                    tint: .blue
                )
            }

            DisclosureGroup {
                VStack(spacing: 12) {
                    ForEach(Array(model.responseOptions.enumerated()), id: \.element.id) { index, option in
                        InterceptorOptionRow(
                            title: option.kind.title,
                            result: option.kind.result,
                            isEnabled: Binding(
                                get: { model.responseOptions[index].isEnabled },
                                set: { model.setResponseEnabled(option.kind, enabled: $0) }
                            ),
                            canDisable: true,
                            canMoveUp: index > 0,
                            canMoveDown: index < model.responseOptions.count - 1,
                            moveUp: { model.moveResponse(option.kind, offset: -1) },
                            moveDown: { model.moveResponse(option.kind, offset: 1) }
                        )
                    }
                }
                .padding(.top, 8)
            } label: {
                ChainSummary(
                    title: "Response chain",
                    names: model.activeResponseChain.map(\.title),
                    tint: .purple
                )
            }
        } header: {
            Text("Active interceptor chains")
        } footer: {
            Text("The local HTTP mock stays enabled so every ordering remains deterministic. Move it earlier to see later request interceptors become skipped.")
        }
        .disabled(model.isActive)
    }

    private var controlsSection: some View {
        Section("Run the experiment") {
            Button {
                model.runFull()
            } label: {
                Label("Run full pipeline", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isActive)

            Button {
                model.step()
            } label: {
                Label(
                    model.runState == .stepping ? "Run next stage" : "Start step-through",
                    systemImage: "forward.frame.fill"
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.bordered)
            .disabled(model.runState == .running)

            Button(role: .destructive) {
                model.reset()
            } label: {
                Label("Reset experiment", systemImage: "arrow.counterclockwise")
            }
            .disabled(model.events.isEmpty && model.runState == .idle)
        }
    }

    private var statusSection: some View {
        Section("Current state") {
            LabeledContent("Stage", value: model.currentEvent?.stage.rawValue ?? stateLabel)
            LabeledContent("Attempt", value: "\(model.attempt)")
            LabeledContent("Response source", value: model.responseSource.rawValue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Next action")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.nextAction)
            }
        }
    }

    private var stateLabel: String {
        switch model.runState {
        case .idle: "Ready"
        case .stepping, .running: "Advancing"
        case .succeeded: "Decoded"
        case .failed: "Failed"
        }
    }
}

private struct PipelineMap: View {
    let currentStage: PipelineStage?

    private let stages: [(PipelineStage, String)] = [
        (.typedRequest, "Requestable"),
        (.builtRequest, "URLRequest"),
        (.requestInterceptors, "Request chain"),
        (.mock, "Mock"),
        (.responseInterceptors, "Response chain"),
        (.validation, "Validate"),
        (.decoding, "Decode"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    Text(stage.1)
                        .font(.caption.weight(currentStage == stage.0 ? .bold : .regular))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(currentStage == stage.0 ? Color.accentColor : Color.secondary.opacity(0.12))
                        .foregroundStyle(currentStage == stage.0 ? .white : .primary)
                        .clipShape(Capsule())
                    if index < stages.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct ChainSummary: View {
    let title: String
    let names: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: "point.3.filled.connected.trianglepath.dotted")
                .font(.headline)
                .foregroundStyle(tint)
            Text(names.isEmpty ? "No active interceptors" : names.joined(separator: " → "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

private struct InterceptorOptionRow: View {
    let title: String
    let result: String
    @Binding var isEnabled: Bool
    let canDisable: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(canDisable == false)

            HStack(spacing: 4) {
                Button(action: moveUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(canMoveUp == false)
                .accessibilityLabel("Move \(title) earlier")

                Button(action: moveDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(canMoveDown == false)
                .accessibilityLabel("Move \(title) later")
            }
        }
    }
}

private struct PipelineEventRow: View {
    let event: PipelineEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                    Spacer()
                    Text("Attempt \(event.attempt)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(event.stage.rawValue)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(event.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var icon: String {
        switch event.state {
        case .current: "circle.inset.filled"
        case .completed: "checkmark.circle.fill"
        case .skipped: "forward.end.circle"
        case .restarted: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch event.state {
        case .current: .accentColor
        case .completed: .green
        case .skipped: .secondary
        case .restarted: .orange
        case .failed: .red
        }
    }
}

private struct RequestComparison: View {
    let before: RequestSnapshot
    let after: RequestSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URLRequest")
                .font(.headline)
            ComparisonLine(label: "Method", before: before.method, after: after.method)
            ComparisonLine(label: "URL", before: before.url, after: after.url, monospaced: true)
            ComparisonLine(
                label: "Headers",
                before: headerSummary(before.headerNames),
                after: headerSummary(after.headerNames)
            )
            ComparisonLine(label: "Body", before: before.bodyMetadata, after: after.bodyMetadata)
        }
    }

    private func headerSummary(_ names: [String]) -> String {
        names.isEmpty ? "None" : "\(names.count): \(names.joined(separator: ", "))"
    }
}

private struct ResponseComparison: View {
    let before: ResponseSnapshot
    let after: ResponseSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HTTP response")
                .font(.headline)
            ComparisonLine(label: "Status", before: "\(before.status)", after: "\(after.status)")
            ComparisonLine(
                label: "Headers",
                before: "\(before.headerNames.count): \(before.headerNames.joined(separator: ", "))",
                after: "\(after.headerNames.count): \(after.headerNames.joined(separator: ", "))"
            )
            ComparisonLine(label: "Body", before: before.bodyMetadata, after: after.bodyMetadata)
        }
    }
}

private struct ComparisonLine: View {
    let label: String
    let before: String
    let after: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(before)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                Text(after)
                    .fontWeight(before == after ? .regular : .semibold)
            }
            .font(monospaced ? .caption.monospaced() : .caption)
            .textSelection(.enabled)
        }
    }
}

#Preview {
    ContentView()
}
