# Bifrost Sample App

This app is a deterministic developer lab for Bifrost's request and response pipeline. It links the parent package locally and executes the real `API.response(for:)` and interceptor protocols without making a network request.

## Run the lab

Open `SampleApp.xcworkspace`, select the `SampleApp` scheme and an iOS 17 or later simulator, then run.

From the repository root, the equivalent XcodeBuildMCP workflow is:

```sh
xcodebuildmcp simulator build-and-run \
  --workspace-path SampleApp/SampleApp.xcworkspace \
  --scheme SampleApp \
  --simulator-name "iPhone 17 Pro"
```

Normal launches use `Bifrost.debug = .normal`, which reports structural lifecycle information without sensitive URL components.

## Explore the pipeline

The lab makes this flow visible:

```text
Requestable → URLRequest → request interceptors → local HTTP mock
            → response interceptors → status validation → decoding
```

Choose a guided preset for request mutation, request restart, request `.return`, response restart, response `.return`, or a thrown failure. You can then:

- Enable or disable curated request and response interceptors.
- Reorder both chains and preview the active order before running.
- Run the complete pipeline or advance between interceptor stages.
- Inspect the original typed request separately from its built `URLRequest`.
- Compare safe URL, method, header-name, body-metadata, status, and response-metadata snapshots.
- See attempt number, response source, current stage, next action, skipped work, and the final decoded value.
- Reset and replay the same local fixture deterministically.

The local HTTP mock is the final required request interceptor. It returns an `InterceptedResponse`, so response interception, status validation, and typed decoding are still performed by Bifrost. Moving another interceptor after the mock demonstrates request-phase skipping without introducing network variability.

Query values, credentials, header values, and bodies are not displayed. The lab shows only explicitly synthetic typed input and safe structural metadata.

## Validation strategy

Bifrost is logic-first, so package tests are the authoritative proof of interceptor ordering, mutation, restart, `.return`, thrown failure, status validation, decoding, transport failure, and cancellation. The sample package adds focused tests for its redaction, preset configuration, and step gate.

Run the library suite:

```sh
xcodebuildmcp swift-package test --package-path .
```

Run the sample-support tests:

```sh
xcodebuildmcp swift-package test --package-path SampleApp/SampleAppPackage
```

There is intentionally no UI-test target: SwiftUI is the inspection surface, not part of Bifrost's public contract. Build and run the app, then manually inspect each preset, alternate ordering, step-through behavior, and reset path.
