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

import XCTest
@testable import Bifrost

final class LoggingTests: XCTestCase {
    private enum TestError: Error {
        case expected
    }

    override func setUp() {
        super.setUp()
        Bifrost.debug = .off
    }

    override func tearDown() {
        Bifrost.debug = .off
        super.tearDown()
    }

    func testEveryEventUsesExpectedLogLevel() {
        let normalEvents: [BifrostLogEvent] = [
            .pipelineRestarted(phase: .request, nextAttempt: 2),
            .requestCancelled,
            .requestFailed(error: TestError.expected),
            .requestStarted(attempt: 1, method: "GET", url: "https://example.com"),
            .requestSucceeded(statusCode: 200, byteCount: 42),
        ]
        let traceEvents: [BifrostLogEvent] = [
            .interceptorRunning(phase: .response, index: 1, count: 2, type: "Interceptor"),
            .requestBody(body: #"{"value":1}"#, byteCount: 11),
            .requestHeaders(["Accept": "application/json"]),
            .requestURL("https://example.com?token=secret"),
            .responseHeaders(["Content-Type": "application/json"]),
            .responseReceived(source: .transport, statusCode: 200, byteCount: 42),
        ]

        for event in normalEvents {
            XCTAssertEqual(event.logLevel, .normal, "\(event) should be a normal event")
        }

        for event in traceEvents {
            XCTAssertEqual(event.logLevel, .trace, "\(event) should be a trace event")
        }
    }

    func testDebugLevelsIncludeOnlyExpectedEventLevels() {
        let expectations: [
            (configured: Bifrost.DebugLogLevel, event: Bifrost.DebugLogLevel, included: Bool)
        ] = [
            (.off, .off, true),
            (.off, .normal, false),
            (.off, .trace, false),
            (.normal, .off, false),
            (.normal, .normal, true),
            (.normal, .trace, false),
            (.trace, .off, true),
            (.trace, .normal, true),
            (.trace, .trace, true),
        ]

        for expectation in expectations {
            XCTAssertEqual(
                expectation.configured.includes(expectation.event),
                expectation.included,
                "\(expectation.configured) including \(expectation.event)"
            )
        }
    }

    func testEveryEventRendersStableStructuredMessage() {
        let expectations: [(event: BifrostLogEvent, message: String)] = [
            (
                .interceptorRunning(
                    phase: .request,
                    index: 2,
                    count: 3,
                    type: "AuthorizationInterceptor"
                ),
                "[interceptor] → running | phase=request index=2/3 type=AuthorizationInterceptor"
            ),
            (
                .pipelineRestarted(phase: .response, nextAttempt: 3),
                "[request] ↻ restarted | phase=response next_attempt=3"
            ),
            (
                .requestBody(body: #"{"value":1}"#, byteCount: 11),
                #"[request] • body | bytes=11 value="{\"value\":1}""#
            ),
            (
                .requestCancelled,
                "[request] • cancelled"
            ),
            (
                .requestFailed(error: TestError.expected),
                "[request] ✗ failed | error=expected"
            ),
            (
                .requestHeaders([
                    "X-Zebra": "last",
                    "Accept": "application/json",
                ]),
                #"[request] • headers | count=2 Accept="application/json" X-Zebra="last""#
            ),
            (
                .requestStarted(
                    attempt: 2,
                    method: "POST",
                    url: "https://example.com/users"
                ),
                "[request] → started | attempt=2 method=POST url=https://example.com/users"
            ),
            (
                .requestSucceeded(statusCode: 204, byteCount: 0),
                "[request] ✓ succeeded | status=204 bytes=0"
            ),
            (
                .requestURL("https://example.com/users?token=secret"),
                "[request] • full URL | value=https://example.com/users?token=secret"
            ),
            (
                .responseHeaders([
                    "X-Zebra": "last",
                    "Content-Type": "application/json",
                ]),
                #"[response] • headers | count=2 Content-Type="application/json" X-Zebra="last""#
            ),
            (
                .responseReceived(
                    source: .requestInterceptor,
                    statusCode: 202,
                    byteCount: 42
                ),
                "[response] ← received | source=request_interceptor status=202 bytes=42"
            ),
        ]

        for expectation in expectations {
            XCTAssertEqual(expectation.event.message, expectation.message)
        }
    }

    func testEmptyHeadersRenderTheirCount() {
        XCTAssertEqual(
            BifrostLogEvent.requestHeaders([:]).message,
            "[request] • headers | count=0"
        )
        XCTAssertEqual(
            BifrostLogEvent.responseHeaders([:]).message,
            "[response] • headers | count=0"
        )
    }

    func testHeaderValuesAreQuotedAndEscaped() {
        XCTAssertEqual(
            BifrostLogEvent.requestHeaders([
                "X-Debug": "line one\n\"line two\"",
            ]).message,
            #"[request] • headers | count=1 X-Debug="line one\n\"line two\"""#
        )
    }

    func testLogMessagesIncludeActiveTraceIdentifier() {
        let message = BifrostLogTrace.$id.withValue("request:123") {
            BifrostLogEvent.requestCancelled.message
        }

        XCTAssertEqual(message, "[request][request:123] • cancelled")
        XCTAssertNil(BifrostLogTrace.id)
    }

    func testNestedTraceIdentifiersRestoreTheirParent() {
        let identifiers = BifrostLogTrace.$id.withValue("outer") {
            let beforeNestedTrace = BifrostLogTrace.id
            let nestedTrace = BifrostLogTrace.$id.withValue("inner") {
                BifrostLogTrace.id
            }
            let afterNestedTrace = BifrostLogTrace.id
            return (beforeNestedTrace, nestedTrace, afterNestedTrace)
        }

        XCTAssertEqual(identifiers.0, "outer")
        XCTAssertEqual(identifiers.1, "inner")
        XCTAssertEqual(identifiers.2, "outer")
        XCTAssertNil(BifrostLogTrace.id)
    }

    func testWithNewIDCreatesAndRestoresTraceIdentifier() async {
        let generatedID = await BifrostLogTrace.withNewID {
            BifrostLogTrace.id
        }

        XCTAssertEqual(generatedID?.count, 8)
        XCTAssertNil(BifrostLogTrace.id)
    }

    func testNormalURLDescriptionRemovesSensitiveComponents() throws {
        let url = try XCTUnwrap(
            URL(string: "https://user:password@example.com/users?api-key=secret&limit=10#fragment")
        )

        XCTAssertEqual(
            BifrostLogURL.normalDescription(for: url),
            "https://example.com/users"
        )
    }

    func testNormalURLDescriptionPreservesNonSensitiveComponents() throws {
        let url = try XCTUnwrap(
            URL(string: "https://example.com:8443/users/a%20b")
        )

        XCTAssertEqual(
            BifrostLogURL.normalDescription(for: url),
            "https://example.com:8443/users/a%20b"
        )
    }

    func testNormalURLDescriptionHandlesMissingURL() {
        XCTAssertEqual(
            BifrostLogURL.normalDescription(for: nil),
            "<missing URL>"
        )
    }

    func testLoggingLevelCanBeChangedOutsideMainActor() async {
        await Task.detached {
            Bifrost.debug = .normal
        }.value

        XCTAssertEqual(Bifrost.debug, .normal)
    }

    func testLoggingConfigurationSupportsConcurrentAccess() async {
        let levels = [
            Bifrost.DebugLogLevel.off,
            .normal,
            .trace,
        ]

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    Bifrost.debug = levels[index % levels.count]
                    _ = Bifrost.debug
                }
            }
        }

        Bifrost.debug = .trace
        XCTAssertEqual(Bifrost.debug, .trace)
    }

    @MainActor
    func testLegacyLoggingSwitchMapsFalseToOff() {
        Bifrost.debug = .trace

        BifrostLogging.isDebugLoggingEnabled = false

        XCTAssertEqual(Bifrost.debug, .off)
        XCTAssertFalse(BifrostLogging.isDebugLoggingEnabled)
    }

    @MainActor
    func testLegacyLoggingSwitchMapsTrueToTrace() {
        BifrostLogging.isDebugLoggingEnabled = true

        XCTAssertEqual(Bifrost.debug, .trace)
        XCTAssertTrue(BifrostLogging.isDebugLoggingEnabled)
    }

    @MainActor
    func testLegacyLoggingSwitchReportsNormalAsEnabled() {
        Bifrost.debug = .normal

        XCTAssertTrue(BifrostLogging.isDebugLoggingEnabled)
    }
}
