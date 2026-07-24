# Inspect request activity

Bifrost reports request lifecycle and interception activity through unified
logging. Diagnostics are off by default and are intended for development.

## Enable request logs

Set the process-wide `Bifrost.debug` level during app startup:

```swift
import Bifrost
import SwiftUI

@main
struct ExampleApp: App {
  init() {
    Bifrost.debug = .normal
  }

  var body: some Scene {
    WindowGroup { ContentView() }
  }
}
```

| Level | Output |
| --- | --- |
| `.off` | No Bifrost logs. |
| `.normal` | Request starts, pipeline restarts, successes, cancellations, and failures. |
| `.trace` | Normal logs plus full URLs, interceptor execution, headers, request bodies, and raw response metadata. |

Normal logs remove URL queries, fragments, and embedded user credentials.
Trace logs can expose credentials or personal data from URLs, header values,
and request bodies. Enable `.trace` only in a trusted debugging environment.

Events from one call share a trace identifier. A restarted pipeline keeps that
identifier and increments its attempt number, which makes a refresh-and-restart
flow possible to follow in Console.

`Bifrost.debug` is safe to read or write from concurrent tasks. Diagnostic
calls are compiled out when the Bifrost module is built without `DEBUG`.

Logs use the `eu.lelfe.bifrost` subsystem and `Bifrost` category.

## Migrate the Boolean switch

The deprecated `BifrostLogging.isDebugLoggingEnabled` property remains
available for source compatibility and is main-actor isolated:

```swift
@MainActor
func enableLegacyDiagnostics() {
  BifrostLogging.isDebugLoggingEnabled = true
}
```

Reading returns `true` for `.normal` or `.trace`. Setting `true` selects
`.trace`; setting `false` selects `.off`. New code should use `Bifrost.debug`.

Next: [Interceptors](interceptors.md) · [Requests and responses](requests-and-responses.md)
