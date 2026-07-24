//
//  Copyright (c) 2026 @mtzaquia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import OSLog

/// Global Bifrost diagnostic configuration.
public enum Bifrost {
    /// The amount of network diagnostic detail emitted by Bifrost in debug builds.
    public enum DebugLogLevel: Equatable, Sendable {
        /// Disables Bifrost request logs.
        case off

        /// Logs request lifecycle events, retries, cancellations, and failures.
        case normal

        /// Includes full URLs, interceptor activity, headers, and bodies in addition to normal logs.
        ///
        /// URLs, header values, and body values can contain credentials or personal data.
        /// Enable this level only while diagnosing requests in a trusted environment.
        case trace
    }

    private static let debugState = BifrostDebugState()

    /// Controls the network diagnostics emitted by Bifrost in debug builds.
    ///
    /// Logging is off by default. This setting has no effect in release builds.
    ///
    /// ```swift
    /// Bifrost.debug = .trace
    /// ```
    public static var debug: DebugLogLevel {
        get { debugState.level }
        set { debugState.level = newValue }
    }
}

/// Legacy Bifrost logging configuration.
@available(*, deprecated, message: "Use Bifrost.debug instead.")
public enum BifrostLogging {
    /// Controls whether detailed Bifrost request logging is enabled.
    ///
    /// Setting this property to `true` is equivalent to setting ``Bifrost/debug``
    /// to ``Bifrost/DebugLogLevel/trace``. Setting it to `false` selects
    /// ``Bifrost/DebugLogLevel/off``.
    @MainActor
    public static var isDebugLoggingEnabled: Bool {
        get { Bifrost.debug != .off }
        set { Bifrost.debug = newValue ? .trace : .off }
    }
}

private final class BifrostDebugState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLevel = Bifrost.DebugLogLevel.off

    var level: Bifrost.DebugLogLevel {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedLevel
        }
        set {
            lock.lock()
            storedLevel = newValue
            lock.unlock()
        }
    }
}

nonisolated let bifrostLog = Logger(
    subsystem: "eu.lelfe.bifrost",
    category: "Bifrost"
)

enum BifrostLogTrace {
    @TaskLocal static var id: String?

    static func withNewID<Result>(
        _ operation: () async throws -> Result
    ) async rethrows -> Result {
#if DEBUG
        let id = String(UUID().uuidString.prefix(8))
        return try await $id.withValue(id, operation: operation)
#else
        return try await operation()
#endif
    }
}

enum BifrostInterceptionPhase: String {
    case request
    case response
}

enum BifrostResponseSource: String {
    case requestInterceptor = "request_interceptor"
    case responseInterceptor = "response_interceptor"
    case transport
}

enum BifrostLogURL {
    static func normalDescription(for url: URL?) -> String {
        guard let url else { return "<missing URL>" }
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }
}

enum BifrostLogEvent {
    case interceptorRunning(phase: BifrostInterceptionPhase, index: Int, count: Int, type: String)
    case pipelineRestarted(phase: BifrostInterceptionPhase, nextAttempt: Int)
    case requestBody(body: String, byteCount: Int)
    case requestCancelled
    case requestFailed(error: any Error)
    case requestHeaders([String: String])
    case requestStarted(attempt: Int, method: String, url: String)
    case requestSucceeded(statusCode: Int, byteCount: Int)
    case requestURL(String)
    case responseHeaders([String: String])
    case responseReceived(source: BifrostResponseSource, statusCode: Int, byteCount: Int)

    var logLevel: Bifrost.DebugLogLevel {
        switch self {
        case .pipelineRestarted,
             .requestCancelled,
             .requestFailed,
             .requestStarted,
             .requestSucceeded:
            .normal

        case .interceptorRunning,
             .requestBody,
             .requestHeaders,
             .requestURL,
             .responseHeaders,
             .responseReceived:
            .trace
        }
    }

    var message: String {
        let trace = BifrostLogTrace.id.map { "[\($0)]" } ?? ""

        return switch self {
        case let .interceptorRunning(phase, index, count, type):
            "[interceptor]\(trace) → running | phase=\(phase.rawValue) index=\(index)/\(count) type=\(type)"
        case let .pipelineRestarted(phase, nextAttempt):
            "[request]\(trace) ↻ restarted | phase=\(phase.rawValue) next_attempt=\(nextAttempt)"
        case let .requestBody(body, byteCount):
            "[request]\(trace) • body | bytes=\(byteCount) value=\(body.debugDescription)"
        case .requestCancelled:
            "[request]\(trace) • cancelled"
        case let .requestFailed(error):
            "[request]\(trace) ✗ failed | error=\(error)"
        case let .requestHeaders(fields):
            "[request]\(trace) • headers | \(fields.logDescription)"
        case let .requestStarted(attempt, method, url):
            "[request]\(trace) → started | attempt=\(attempt) method=\(method) url=\(url)"
        case let .requestSucceeded(statusCode, byteCount):
            "[request]\(trace) ✓ succeeded | status=\(statusCode) bytes=\(byteCount)"
        case let .requestURL(url):
            "[request]\(trace) • full URL | value=\(url)"
        case let .responseHeaders(fields):
            "[response]\(trace) • headers | \(fields.logDescription)"
        case let .responseReceived(source, statusCode, byteCount):
            "[response]\(trace) ← received | source=\(source.rawValue) status=\(statusCode) bytes=\(byteCount)"
        }
    }
}

extension Logger {
    func bifrostDebug(_ event: @autoclosure () -> BifrostLogEvent) {
#if DEBUG
        let configuredLevel = Bifrost.debug
        guard configuredLevel != .off else { return }

        let event = event()
        guard configuredLevel.includes(event.logLevel) else { return }
        debug("\(event.message, privacy: .public)")
#endif
    }
}

extension Bifrost.DebugLogLevel {
    func includes(_ eventLevel: Self) -> Bool {
        switch (self, eventLevel) {
        case (.trace, _), (.normal, .normal), (.off, .off):
            true
        default:
            false
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    var logDescription: String {
        guard !isEmpty else { return "count=0" }

        let values = sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.debugDescription)" }
            .joined(separator: " ")
        return "count=\(count) \(values)"
    }
}
