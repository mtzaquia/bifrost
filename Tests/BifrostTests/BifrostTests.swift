//
//  BifrostTests.swift
//
//  Copyright (c) 2021 @mtzaquia
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

@MainActor
final class BifrostTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        URLProtocolStub.setHandler(nil)
        URLProtocolStub.setObserver(nil)
    }

    override func tearDown() async throws {
        URLProtocolStub.setHandler(nil)
        URLProtocolStub.setObserver(nil)
        try await super.tearDown()
    }

    override class func setUp() {
        super.setUp()

        MainActor.assumeIsolated {
            BifrostLogging.isDebugLoggingEnabled = true
        }
    }

    func testRequestInterceptorMutatesBuiltURLRequestBeforeTransport() async throws {
        let requestRecorder = RequestRecorder()

        URLProtocolStub.setObserver { request in
            requestRecorder.record(request)
        }

        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/items/mutated?q=rewritten")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Header"), "api")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-Header"), "intercepted")

            let body = try XCTUnwrap(requestBodyData(from: request))
            let payload = try JSONDecoder().decode(ExampleRequest.Payload.self, from: body)
            XCTAssertEqual(payload, .init(value: "updated-body"))

            return StubbedResponse(
                body: #"{"value":"network"}"#,
                statusCode: 200,
                headers: ["X-Transport": "live"]
            )
        }

        let api = TestAPI(
            requestInterceptors: [
                DefaultHeadersInterceptor(),
                MutatingRequestInterceptor()
            ],
            responseInterceptors: [],
            urlSession: makeURLSession()
        )

        let response = try await api.response(
            for: ExampleRequest(
                pathComponent: "original",
                queryValue: "initial",
                headerValue: "request",
                payloadValue: "body"
            )
        )

        XCTAssertEqual(response, .init(value: "network"))
        let requestCount = requestRecorder.count()
        XCTAssertEqual(requestCount, 1)
    }

    func testMultipleRequestInterceptorsComposeInOrder() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/items/base-first-second?q=start-one-two")

            return StubbedResponse(
                body: #"{"value":"ordered"}"#,
                statusCode: 200
            )
        }

        let api = TestAPI(
            requestInterceptors: [
                AppendingRequestInterceptor(pathSuffix: "-first", querySuffix: "-one"),
                AppendingRequestInterceptor(pathSuffix: "-second", querySuffix: "-two")
            ],
            responseInterceptors: [],
            urlSession: makeURLSession()
        )

        let response = try await api.response(
            for: ExampleRequest(
                pathComponent: "base",
                queryValue: "start",
                headerValue: "request",
                payloadValue: "body"
            )
        )

        XCTAssertEqual(response, .init(value: "ordered"))
    }

    func testRequestInterceptorCanShortCircuitWithMockedResponse() async throws {
        let requestRecorder = RequestRecorder()
        let responseRecorder = ResponseRecorder()

        URLProtocolStub.setObserver { request in
            requestRecorder.record(request)
        }

        let api = TestAPI(
            requestInterceptors: [
                MockingRequestInterceptor(
                    body: .init(value: "mocked"),
                    statusCode: 202,
                    headers: ["X-Mocked": "yes"]
                )
            ],
            responseInterceptors: [CapturingResponseInterceptor(recorder: responseRecorder)],
            urlSession: makeURLSession()
        )

        let response = try await api.response(
            for: ExampleRequest(
                pathComponent: "ignored",
                queryValue: "ignored",
                headerValue: "ignored",
                payloadValue: "ignored"
            )
        )

        XCTAssertEqual(response, .init(value: "mocked"))
        let requestCount = requestRecorder.count()
        let responseSnapshot = responseRecorder.snapshot()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(responseSnapshot.statusCodes, [202])
        XCTAssertEqual(responseSnapshot.headers.first?["X-Mocked"], "yes")
        XCTAssertEqual(responseSnapshot.bodies, [.init(value: "mocked")])
    }

    func testResponseInterceptorsCanInspectMetadataAndMutateBody() async throws {
        let responseRecorder = ResponseRecorder()

        URLProtocolStub.setHandler { _ in
            StubbedResponse(
                body: #"{"value":"network"}"#,
                statusCode: 201,
                headers: ["X-Trace": "123"]
            )
        }

        let api = TestAPI(
            requestInterceptors: [],
            responseInterceptors: [
                CapturingResponseInterceptor(recorder: responseRecorder),
                MutatingResponseInterceptor(suffix: "-mutated")
            ],
            urlSession: makeURLSession()
        )

        let response = try await api.response(
            for: ExampleRequest(
                pathComponent: "value",
                queryValue: "q",
                headerValue: "header",
                payloadValue: "body"
            )
        )

        XCTAssertEqual(response, .init(value: "network-mutated"))
        let responseSnapshot = responseRecorder.snapshot()
        XCTAssertEqual(responseSnapshot.statusCodes, [201])
        XCTAssertEqual(responseSnapshot.headers.first?["X-Trace"], "123")
        XCTAssertEqual(responseSnapshot.bodies, [.init(value: "network")])
    }

    func testResponseInterceptorReturnStopsChain() async throws {
        let responseRecorder = ResponseRecorder()

        URLProtocolStub.setHandler { _ in
            StubbedResponse(
                body: #"{"value":"network"}"#,
                statusCode: 200,
                headers: ["X-Trace": "network"]
            )
        }

        let api = TestAPI(
            requestInterceptors: [],
            responseInterceptors: [
                ShortCircuitingResponseInterceptor(
                    body: .init(value: "short-circuited"),
                    statusCode: 299,
                    headers: ["X-Trace": "short"]
                ),
                CapturingResponseInterceptor(recorder: responseRecorder)
            ],
            urlSession: makeURLSession()
        )

        let response = try await api.response(
            for: ExampleRequest(
                pathComponent: "value",
                queryValue: "q",
                headerValue: "header",
                payloadValue: "body"
            )
        )

        XCTAssertEqual(response, .init(value: "short-circuited"))
        let responseSnapshot = responseRecorder.snapshot()
        XCTAssertEqual(responseSnapshot.statusCodes, [])
    }

    func testThrownRequestInterceptorErrorPropagates() async throws {
        let api = TestAPI(
            requestInterceptors: [ThrowingRequestInterceptor()],
            responseInterceptors: [],
            urlSession: makeURLSession()
        )

        do {
            _ = try await api.response(
                for: ExampleRequest(
                    pathComponent: "value",
                    queryValue: "q",
                    headerValue: "header",
                    payloadValue: "body"
                )
            )
            XCTFail("Expected request interceptor to throw")
        } catch {
            XCTAssertEqual(error as? TestError, .request)
        }
    }

    func testThrownResponseInterceptorErrorPropagates() async throws {
        URLProtocolStub.setHandler { _ in
            StubbedResponse(
                body: #"{"value":"network"}"#,
                statusCode: 200
            )
        }

        let api = TestAPI(
            requestInterceptors: [],
            responseInterceptors: [ThrowingResponseInterceptor()],
            urlSession: makeURLSession()
        )

        do {
            _ = try await api.response(
                for: ExampleRequest(
                    pathComponent: "value",
                    queryValue: "q",
                    headerValue: "header",
                    payloadValue: "body"
                )
            )
            XCTFail("Expected response interceptor to throw")
        } catch {
            XCTAssertEqual(error as? TestError, .response)
        }
    }

    func testRequestWithoutInterceptorsUsesTransportPath() async throws {
        let requestRecorder = RequestRecorder()

        URLProtocolStub.setObserver { request in
            requestRecorder.record(request)
        }

        URLProtocolStub.setHandler { _ in
            StubbedResponse(
                body: #"{"value":"transport"}"#,
                statusCode: 200
            )
        }

        let api = TestAPI(
            requestInterceptors: [],
            responseInterceptors: [],
            urlSession: makeURLSession()
        )

        let response = try await api.response(
            for: ExampleRequest(
                pathComponent: "value",
                queryValue: "q",
                headerValue: "header",
                payloadValue: "body"
            )
        )

        XCTAssertEqual(response, .init(value: "transport"))
        let requestCount = requestRecorder.count()
        XCTAssertEqual(requestCount, 1)
    }

    func testResponseInterceptorCanRefreshAfter401AndResumeChain() async throws {
        let requestRecorder = RequestRecorder()
        let flow = AuthFlow(urlSession: makeURLSession())

        URLProtocolStub.setObserver { request in
            requestRecorder.record(request)
        }

        URLProtocolStub.setHandler { request in
            switch request.url?.lastPathComponent {
            case "protected":
                switch request.value(forHTTPHeaderField: "Authorization") {
                case "Bearer stale-token":
                    return StubbedResponse(
                        body: #"{"error":"unauthorized"}"#,
                        statusCode: 401
                    )
                case "Bearer fresh-token":
                    return StubbedResponse(
                        body: #"{"value":"protected"}"#,
                        statusCode: 200,
                        headers: ["X-Transport": "retried"]
                    )
                default:
                    XCTFail("Unexpected authorization header: \(String(describing: request.value(forHTTPHeaderField: "Authorization")))")
                    return StubbedResponse(body: #"{"error":"unexpected"}"#, statusCode: 500)
                }
            case "refresh":
                return StubbedResponse(
                    body: #"{"token":"fresh-token"}"#,
                    statusCode: 200
                )
            default:
                XCTFail("Unexpected path: \(String(describing: request.url?.path))")
                return StubbedResponse(body: #"{"error":"unexpected"}"#, statusCode: 500)
            }
        }

        let response = try await flow.api.response(for: ProtectedRequest())

        XCTAssertEqual(response, .init(value: "protected-resumed", error: nil))
        XCTAssertEqual(flow.tokenStore.token(), "fresh-token")

        let requests = requestRecorder.snapshot()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.compactMap(\.url?.lastPathComponent), ["protected", "refresh", "protected"])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer stale-token")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer fresh-token")
    }

    func testUnsuccessfulStatusCodeIsThrownAfterResponseInterceptors() async throws {
        let statusRecorder = StatusRecorder()

        URLProtocolStub.setHandler { _ in
            StubbedResponse(
                body: #"{"value":null,"error":"unauthorized"}"#,
                statusCode: 401
            )
        }

        let api = ProtectedAPI(
            requestInterceptors: [],
            responseInterceptors: [StatusRecordingResponseInterceptor(recorder: statusRecorder)],
            urlSession: makeURLSession()
        )

        do {
            _ = try await api.response(for: ProtectedRequest())
            XCTFail("Expected 401 to be surfaced after the response phase")
        } catch {
            guard case BifrostError.unsuccessfulStatusCode(401) = error else {
                XCTFail("Expected unsuccessfulStatusCode(401), got \(error)")
                return
            }
        }

        XCTAssertEqual(statusRecorder.snapshot(), [401])
    }

    func testMockedUnsuccessfulResponseReachesResponseInterceptorsBeforeErrorSurfacing() async throws {
        let statusRecorder = StatusRecorder()

        let api = TestAPI(
            requestInterceptors: [
                MockingRequestInterceptor(
                    body: .init(value: "mocked"),
                    statusCode: 418,
                    headers: ["X-Mocked": "yes"]
                )
            ],
            responseInterceptors: [
                StatusRecordingResponseInterceptor(recorder: statusRecorder),
                NormalizingStatusCodeInterceptor(from: 418, to: 200)
            ],
            urlSession: makeURLSession()
        )

        let response = try await api.response(
            for: ExampleRequest(
                pathComponent: "ignored",
                queryValue: "ignored",
                headerValue: "ignored",
                payloadValue: "ignored"
            )
        )

        XCTAssertEqual(response, .init(value: "mocked"))
        XCTAssertEqual(statusRecorder.snapshot(), [418])
    }
}

private struct TestAPI: API {
    let baseURL = URL(string: "https://example.com/api")!
    let requestInterceptors: [any RequestInterceptor]
    let responseInterceptors: [any ResponseInterceptor]
    let urlSession: URLSession
}

private struct ExampleRequest: Requestable {
    var pathComponent: String
    var queryValue: String
    var headerValue: String
    var payloadValue: String

    var method: HTTPMethod { .post }
    var path: String { "items/\(pathComponent)" }
    var headerFields: [String : String] { ["X-Request-Header": headerValue] }

    func queryParameters() throws -> [URLQueryItem] {
        [URLQueryItem(name: "q", value: queryValue)]
    }

    func bodyParameters(_ encoder: JSONEncoder) throws -> Data? {
        try encoder.encode(Payload(value: payloadValue))
    }

    struct Payload: Codable, Equatable, Sendable {
        let value: String
    }

    struct Response: Codable, Equatable, Sendable {
        let value: String
    }
}

private protocol AuthenticatedRequest {}

private struct ProtectedRequest: Requestable, AuthenticatedRequest {
    var path: String { "protected" }

    struct Response: Codable, Equatable, Sendable {
        let value: String?
        let error: String?
    }
}

private struct RefreshTokenRequest: Requestable {
    var path: String { "refresh" }

    struct Response: Codable, Equatable, Sendable {
        let token: String
    }
}

private final class TokenStore: @unchecked Sendable {
    private let lock = NSLock()
    private var currentToken: String

    init(token: String) {
        currentToken = token
    }

    func token() -> String {
        lock.lock()
        defer { lock.unlock() }
        return currentToken
    }

    func setToken(_ token: String) {
        lock.lock()
        defer { lock.unlock() }
        currentToken = token
    }
}

private final class AuthFlow: @unchecked Sendable {
    let urlSession: URLSession
    let tokenStore = TokenStore(token: "stale-token")

    init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    var api: AuthenticatedAPI {
        AuthenticatedAPI(flow: self)
    }
}

private struct AuthenticatedAPI: API {
    let flow: AuthFlow
    let baseURL = URL(string: "https://example.com/api")!

    var urlSession: URLSession { flow.urlSession }
    var requestInterceptors: [any RequestInterceptor] { [InjectingTokenInterceptor(flow: flow)] }
    var responseInterceptors: [any ResponseInterceptor] {
        [
            RefreshingTokenResponseInterceptor(flow: flow),
            ResumingProtectedResponseInterceptor()
        ]
    }
}

private struct ProtectedAPI: API {
    let baseURL = URL(string: "https://example.com/api")!
    let requestInterceptors: [any RequestInterceptor]
    let responseInterceptors: [any ResponseInterceptor]
    let urlSession: URLSession
}

private struct DefaultHeadersInterceptor: RequestInterceptor {
    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request : Requestable {
        context.urlRequest.setValue("api", forHTTPHeaderField: "X-API-Header")
        return .continue
    }
}

private struct MutatingRequestInterceptor: RequestInterceptor {
    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request : Requestable {
        guard let exampleRequest = context.request as? ExampleRequest else {
            return .continue
        }

        XCTAssertEqual(exampleRequest.pathComponent, "original")
        XCTAssertEqual(context.urlRequest.url?.absoluteString, "https://example.com/api/items/original?q=initial")
        XCTAssertEqual(context.urlRequest.httpMethod, "POST")
        XCTAssertEqual(context.urlRequest.value(forHTTPHeaderField: "X-API-Header"), "api")
        XCTAssertEqual(context.urlRequest.value(forHTTPHeaderField: "X-Request-Header"), "request")

        context.urlRequest.url = URL(string: "https://example.com/api/items/mutated?q=rewritten")!
        context.urlRequest.setValue("intercepted", forHTTPHeaderField: "X-Request-Header")
        context.urlRequest.httpBody = try JSONEncoder().encode(ExampleRequest.Payload(value: "updated-body"))
        return .continue
    }
}

private struct AppendingRequestInterceptor: RequestInterceptor {
    let pathSuffix: String
    let querySuffix: String

    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request : Requestable {
        guard context.request is ExampleRequest else {
            return .continue
        }

        guard
            let url = context.urlRequest.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw URLError(.badURL)
        }

        components.path += pathSuffix
        components.queryItems = components.queryItems?.map { item in
            guard item.name == "q" else {
                return item
            }

            return URLQueryItem(name: item.name, value: (item.value ?? "") + querySuffix)
        }

        context.urlRequest.url = components.url
        return .continue
    }
}

private struct MockingRequestInterceptor: RequestInterceptor {
    let body: ExampleRequest.Response
    let statusCode: Int
    let headers: [String: String]

    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request : Requestable {
        guard context.request is ExampleRequest else {
            return .continue
        }

        let httpResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/mocked")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )
        )

        return .return(
            InterceptedResponse(
                body: try JSONEncoder().encode(body),
                httpResponse: httpResponse
            )
        )
    }
}

private struct InjectingTokenInterceptor: RequestInterceptor {
    let flow: AuthFlow

    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request : Requestable {
        guard context.request is any AuthenticatedRequest else {
            return .continue
        }

        context.urlRequest.setValue("Bearer \(flow.tokenStore.token())", forHTTPHeaderField: "Authorization")
        return .continue
    }
}

private struct ThrowingRequestInterceptor: RequestInterceptor {
    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request : Requestable {
        throw TestError.request
    }
}

private struct ResumingProtectedResponseInterceptor: ResponseInterceptor {
    func intercept(
        _ response: inout InterceptedResponse,
        retry: () async throws -> InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        guard response.headerFields["X-Auth-Recovered"] == "true" else {
            return .continue
        }

        let body = try JSONDecoder().decode(ProtectedRequest.Response.self, from: response.body)

        guard let value = body.value else {
            return .continue
        }

        response.body = try JSONEncoder().encode(
            ProtectedRequest.Response(value: value + "-resumed", error: nil)
        )
        return .continue
    }
}

private struct RefreshingTokenResponseInterceptor: ResponseInterceptor {
    let flow: AuthFlow

    func intercept(
        _ response: inout InterceptedResponse,
        retry: () async throws -> InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        guard response.statusCode == 401 else {
            return .continue
        }

        let refreshResponse = try await flow.api.response(for: RefreshTokenRequest())
        flow.tokenStore.setToken(refreshResponse.token)

        var retriedResponse = try await retry()
        retriedResponse.httpResponse = HTTPURLResponse(
            url: retriedResponse.httpResponse.url!,
            statusCode: retriedResponse.statusCode,
            httpVersion: nil,
            headerFields: retriedResponse.headerFields.merging(["X-Auth-Recovered": "true"]) { _, new in new }
        )!

        response = retriedResponse
        return .continue
    }
}

private struct CapturingResponseInterceptor: ResponseInterceptor {
    let recorder: ResponseRecorder

    func intercept(
        _ response: inout InterceptedResponse,
        retry: () async throws -> InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        let body = try JSONDecoder().decode(ExampleRequest.Response.self, from: response.body)

        recorder.record(
            statusCode: response.statusCode,
            headers: response.headerFields,
            body: body
        )

        return .continue
    }
}

private struct MutatingResponseInterceptor: ResponseInterceptor {
    let suffix: String

    func intercept(
        _ response: inout InterceptedResponse,
        retry: () async throws -> InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        let body = try JSONDecoder().decode(ExampleRequest.Response.self, from: response.body)

        response.body = try JSONEncoder().encode(
            ExampleRequest.Response(value: body.value + suffix)
        )
        return .continue
    }
}

private struct ShortCircuitingResponseInterceptor: ResponseInterceptor {
    let body: ExampleRequest.Response
    let statusCode: Int
    let headers: [String: String]

    func intercept(
        _ response: inout InterceptedResponse,
        retry: () async throws -> InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        let httpResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: response.httpResponse.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )
        )

        return .return(
            InterceptedResponse(
                body: try JSONEncoder().encode(body),
                httpResponse: httpResponse
            )
        )
    }
}

private struct ThrowingResponseInterceptor: ResponseInterceptor {
    func intercept(
        _ response: inout InterceptedResponse,
        retry: () async throws -> InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        throw TestError.response
    }
}

private struct StatusRecordingResponseInterceptor: ResponseInterceptor {
    let recorder: StatusRecorder

    func intercept(
        _ response: inout InterceptedResponse,
        retry: () async throws -> InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        recorder.record(response.statusCode)
        return .continue
    }
}

private struct NormalizingStatusCodeInterceptor: ResponseInterceptor {
    let from: Int
    let to: Int

    func intercept(
        _ response: inout InterceptedResponse,
        retry: () async throws -> InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        guard response.statusCode == from else {
            return .continue
        }

        response.httpResponse = HTTPURLResponse(
            url: response.httpResponse.url!,
            statusCode: to,
            httpVersion: nil,
            headerFields: response.headerFields
        )!

        return .continue
    }
}

private enum TestError: Error, Equatable {
    case request
    case response
}

private struct StubbedResponse: Sendable {
    let body: String
    let statusCode: Int
    let headers: [String: String]

    init(body: String, statusCode: Int, headers: [String: String] = [:]) {
        self.body = body
        self.statusCode = statusCode
        self.headers = headers
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func snapshot() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private final class ResponseRecorder: @unchecked Sendable {
    struct Snapshot: Sendable {
        let statusCodes: [Int]
        let headers: [[String: String]]
        let bodies: [ExampleRequest.Response]
    }

    private let lock = NSLock()
    private var statusCodes: [Int] = []
    private var headers: [[String: String]] = []
    private var bodies: [ExampleRequest.Response] = []

    func record(statusCode: Int, headers: [String: String], body: ExampleRequest.Response) {
        lock.lock()
        defer { lock.unlock() }
        statusCodes.append(statusCode)
        self.headers.append(headers)
        bodies.append(body)
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(statusCodes: statusCodes, headers: headers, bodies: bodies)
    }
}

private final class StatusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [Int] = []

    func record(_ status: Int) {
        lock.lock()
        defer { lock.unlock() }
        statuses.append(status)
    }

    func snapshot() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return statuses
    }
}

private final class URLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> StubbedResponse
    typealias Observer = (URLRequest) -> Void

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var observer: Observer?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (observer, handler) = Self.loadState()

            observer?(request)

            guard let handler else {
                throw URLError(.badServerResponse)
            }

            let stubbedResponse = try handler(request)
            guard
                let url = request.url,
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: stubbedResponse.statusCode,
                    httpVersion: nil,
                    headerFields: stubbedResponse.headers
                )
            else {
                throw URLError(.badServerResponse)
            }

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(stubbedResponse.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func setHandler(_ handler: Handler?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    static func setObserver(_ observer: Observer?) {
        lock.lock()
        defer { lock.unlock() }
        self.observer = observer
    }

    private static func loadState() -> (Observer?, Handler?) {
        lock.lock()
        defer { lock.unlock() }
        return (observer, handler)
    }
}

private func makeURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
}

private func requestBodyData(from request: URLRequest) -> Data? {
    if let httpBody = request.httpBody {
        return httpBody
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var body = Data()

    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: bufferSize)

        if count < 0 {
            return nil
        }

        if count == 0 {
            break
        }

        body.append(buffer, count: count)
    }

    return body
}
