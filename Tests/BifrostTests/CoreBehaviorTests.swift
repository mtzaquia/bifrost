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

extension BifrostTests {
    func testHTTPMethodRawValuesMatchHTTPTokens() {
        XCTAssertEqual(HTTPMethod.get.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.patch.rawValue, "PATCH")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
    }

    func testAPIDefaultsProvideSharedSessionAndEmptyCustomization() {
        let api = MinimalCoreAPI()

        XCTAssertTrue(api.urlSession === URLSession.shared)
        XCTAssertEqual(api.queryParameters(), [])
        XCTAssertTrue(api.requestInterceptors.isEmpty)
        XCTAssertTrue(api.responseInterceptors.isEmpty)
    }

    func testRequestableDefaultsUseGetWithNoHeaders() {
        let request = CoreQueryRequest(
            searchTerm: "swift",
            tags: ["ios"],
            optional: nil
        )

        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.headerFields, [:])
    }

    func testDefaultGetEncodingBuildsRepeatedQueryItemsAndNoBody() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(requestBodyData(from: request))

            let components = try XCTUnwrap(
                request.url.flatMap {
                    URLComponents(url: $0, resolvingAgainstBaseURL: false)
                }
            )
            let queryItems = components.queryItems ?? []

            XCTAssertEqual(components.path, "/api/search")
            XCTAssertEqual(queryItems.filter { $0.name == "searchTerm" }.map(\.value), ["swift ui"])
            XCTAssertEqual(
                Set(queryItems.filter { $0.name == "tags" }.compactMap(\.value)),
                Set(["ios", "macos"])
            )
            XCTAssertFalse(queryItems.contains { $0.name == "optional" })

            return .json(#"{"someValue":"decoded"}"#)
        }

        let response = try await CoreAPI().response(
            for: CoreQueryRequest(
                searchTerm: "swift ui",
                tags: ["ios", "macos"],
                optional: nil
            )
        )

        XCTAssertEqual(response, CoreResponse(someValue: "decoded"))
    }

    func testDefaultPostEncodingPlacesPropertiesInJSONBody() async throws {
        try await assertDefaultBodyRequest(
            CoreBodyRequest<PostMethod>(someValue: "post"),
            expectedMethod: "POST"
        )
    }

    func testDefaultPutEncodingPlacesPropertiesInJSONBody() async throws {
        try await assertDefaultBodyRequest(
            CoreBodyRequest<PutMethod>(someValue: "put"),
            expectedMethod: "PUT"
        )
    }

    func testDefaultPatchEncodingPlacesPropertiesInJSONBody() async throws {
        try await assertDefaultBodyRequest(
            CoreBodyRequest<PatchMethod>(someValue: "patch"),
            expectedMethod: "PATCH"
        )
    }

    func testDefaultDeleteEncodingHasNeitherQueryNorBody() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertNil(request.url?.query)
            XCTAssertNil(requestBodyData(from: request))
            return .json(#"{"someValue":"deleted"}"#)
        }

        let response = try await CoreAPI().response(
            for: CoreBodyRequest<DeleteMethod>(someValue: "not-sent")
        )

        XCTAssertEqual(response, CoreResponse(someValue: "deleted"))
    }

    func testBaseAPIAndRequestQueryItemsComposeInOrder() async throws {
        let api = CoreAPI(
            baseURL: URL(string: "https://example.com/api?base=1")!,
            queryItems: [
                URLQueryItem(name: "shared", value: "api"),
            ]
        )

        URLProtocolStub.setHandler { request in
            let components = try XCTUnwrap(
                request.url.flatMap {
                    URLComponents(url: $0, resolvingAgainstBaseURL: false)
                }
            )

            XCTAssertEqual(
                components.queryItems,
                [
                    URLQueryItem(name: "base", value: "1"),
                    URLQueryItem(name: "shared", value: "api"),
                    URLQueryItem(name: "shared", value: "request"),
                ]
            )
            return .json(#"{"someValue":"composed"}"#)
        }

        let response = try await api.response(
            for: ExplicitCoreRequest(
                path: "items",
                queryItems: [
                    URLQueryItem(name: "shared", value: "request"),
                ]
            )
        )

        XCTAssertEqual(response, CoreResponse(someValue: "composed"))
    }

    func testEmptyRequestPathUsesBaseURLWithoutAppendingSlash() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api")
            return .json(#"{"someValue":"base"}"#)
        }

        let response = try await CoreAPI().response(for: EmptyPathCoreRequest())

        XCTAssertEqual(response, CoreResponse(someValue: "base"))
    }

    func testRequestHeadersAreAppliedToTransportRequest() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), "request-123")
            return .json(#"{"someValue":"headers"}"#)
        }

        let response = try await CoreAPI().response(
            for: ExplicitCoreRequest(
                path: "headers",
                headers: [
                    "Accept": "application/json",
                    "X-Request-ID": "request-123",
                ]
            )
        )

        XCTAssertEqual(response, CoreResponse(someValue: "headers"))
    }

    func testCustomJSONEncoderIsUsedForRequestBody() async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let api = CoreAPI(encoder: encoder)

        URLProtocolStub.setHandler { request in
            let body = try XCTUnwrap(requestBodyData(from: request))
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: String]
            )

            XCTAssertEqual(object, ["some_value": "encoded"])
            return .json(#"{"someValue":"response"}"#)
        }

        _ = try await api.response(
            for: CoreBodyRequest<PostMethod>(someValue: "encoded")
        )
    }

    func testCustomJSONDecoderIsUsedForResponseBody() async throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let api = CoreAPI(decoder: decoder)

        URLProtocolStub.setHandler { _ in
            .json(#"{"some_value":"decoded"}"#)
        }

        let response = try await api.response(
            for: CoreBodyRequest<PostMethod>(someValue: "request")
        )

        XCTAssertEqual(response, CoreResponse(someValue: "decoded"))
    }

    func testEmptyResponseDoesNotAttemptToDecodeBody() async throws {
        URLProtocolStub.setHandler { _ in
            StubbedResponse(body: "", statusCode: 204)
        }

        _ = try await CoreAPI().response(for: EmptyCoreRequest())
    }

    func testInvalidJSONPropagatesDecodingError() async throws {
        URLProtocolStub.setHandler { _ in
            StubbedResponse(body: "not-json", statusCode: 200)
        }

        do {
            _ = try await CoreAPI().response(for: EmptyPathCoreRequest())
            XCTFail("Expected decoding to fail")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testResponseInterceptorsRunBeforeDecodingFailure() async throws {
        let recorder = CorePipelineRecorder()
        URLProtocolStub.setHandler { _ in
            StubbedResponse(body: "not-json", statusCode: 200)
        }
        let api = CoreAPI(
            responseInterceptors: [
                CountingResponseInterceptor(recorder: recorder),
            ]
        )

        do {
            _ = try await api.response(for: EmptyPathCoreRequest())
            XCTFail("Expected decoding to fail")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }

        XCTAssertEqual(recorder.laterResponseInterceptorCount, 1)
    }

    func testDefaultQueryEncodingErrorPreventsTransport() async throws {
        let recorder = CorePipelineRecorder()
        URLProtocolStub.setObserver { _ in recorder.recordTransport() }

        do {
            _ = try await CoreAPI().response(for: ThrowingQueryRequest())
            XCTFail("Expected query encoding to fail")
        } catch {
            XCTAssertEqual(error as? CoreTestError, .encoding)
        }

        XCTAssertEqual(recorder.transportCount, 0)
    }

    func testDefaultBodyEncodingErrorPreventsTransport() async throws {
        let recorder = CorePipelineRecorder()
        URLProtocolStub.setObserver { _ in recorder.recordTransport() }

        do {
            _ = try await CoreAPI().response(for: ThrowingBodyRequest())
            XCTFail("Expected body encoding to fail")
        } catch {
            XCTAssertEqual(error as? CoreTestError, .encoding)
        }

        XCTAssertEqual(recorder.transportCount, 0)
    }

    func testTransportErrorPropagatesWithoutResponseInterception() async throws {
        let recorder = CorePipelineRecorder()
        URLProtocolStub.setHandler { _ in
            throw URLError(.timedOut)
        }
        let api = CoreAPI(
            responseInterceptors: [
                CountingResponseInterceptor(recorder: recorder),
            ]
        )

        do {
            _ = try await api.response(for: EmptyPathCoreRequest())
            XCTFail("Expected transport to fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }

        XCTAssertEqual(recorder.laterResponseInterceptorCount, 0)
    }

    func testCancelledTransportPreservesCancellationCode() async throws {
        let recorder = CorePipelineRecorder()
        URLProtocolStub.setHandler { _ in
            throw URLError(.cancelled)
        }
        let api = CoreAPI(
            responseInterceptors: [
                CountingResponseInterceptor(recorder: recorder),
            ]
        )

        do {
            _ = try await api.response(for: EmptyPathCoreRequest())
            XCTFail("Expected transport cancellation")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }

        XCTAssertEqual(recorder.laterResponseInterceptorCount, 0)
    }

    func testNonHTTPResponseIsRejected() async throws {
        let api = CoreAPI(session: makeNonHTTPURLSession())

        do {
            _ = try await api.response(for: EmptyPathCoreRequest())
            XCTFail("Expected a non-HTTP response to fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
    }

    func testUnsuccessfulStatusPreservesExactCode() async throws {
        URLProtocolStub.setHandler { _ in
            StubbedResponse(body: #"{"error":"bad request"}"#, statusCode: 400)
        }

        do {
            _ = try await CoreAPI().response(for: EmptyPathCoreRequest())
            XCTFail("Expected unsuccessful status")
        } catch {
            guard case BifrostError.unsuccessfulStatusCode(let statusCode) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(statusCode, 400)
        }
    }

    func testBifrostErrorDescriptionIncludesStatusCode() {
        let error = BifrostError.unsuccessfulStatusCode(418)

        XCTAssertTrue(error.localizedDescription.contains("418"))
    }

    func testDictionaryEncoderAppliesConfiguredStrategies() throws {
        let encoder = DictionaryEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.dataEncodingStrategy = .base64
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "positive-infinity",
            negativeInfinity: "negative-infinity",
            nan: "not-a-number"
        )
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let dictionary = try encoder.encode(
            DictionaryPayload(
                createdAt: Date(timeIntervalSince1970: 123),
                rawData: Data([0, 1]),
                floatingPoint: .infinity,
                tags: ["one", "two"],
                optional: nil
            )
        )

        XCTAssertEqual((dictionary["created_at"] as? NSNumber)?.doubleValue, 123)
        XCTAssertEqual(dictionary["raw_data"] as? String, "AAE=")
        XCTAssertEqual(dictionary["floating_point"] as? String, "positive-infinity")
        XCTAssertEqual(dictionary["tags"] as? [String], ["one", "two"])
        XCTAssertNil(dictionary["optional"])
    }

    func testInterceptedResponseExposesMutableBodyStatusAndNormalizedHeaders() throws {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/items")!,
                statusCode: 201,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "X-Count": "2",
                ]
            )
        )
        var intercepted = InterceptedResponse(
            body: Data(#"{"value":"initial"}"#.utf8),
            httpResponse: response
        )

        XCTAssertEqual(intercepted.statusCode, 201)
        XCTAssertEqual(intercepted.headerFields["Content-Type"], "application/json")
        XCTAssertEqual(intercepted.headerFields["X-Count"], "2")

        intercepted.body = Data(#"{"value":"mutated"}"#.utf8)
        intercepted.httpResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: response.url!,
                statusCode: 202,
                httpVersion: nil,
                headerFields: nil
            )
        )

        XCTAssertEqual(intercepted.statusCode, 202)
        XCTAssertEqual(String(decoding: intercepted.body, as: UTF8.self), #"{"value":"mutated"}"#)
    }

    func testInterceptionContextKeepsOriginalRequestWhileURLRequestMutates() {
        let original = ExplicitCoreRequest(path: "original")
        var context = InterceptionContext(
            request: original,
            urlRequest: URLRequest(url: URL(string: "https://example.com/original")!)
        )

        context.urlRequest.url = URL(string: "https://example.com/mutated")
        context.urlRequest.setValue("yes", forHTTPHeaderField: "X-Mutated")

        XCTAssertEqual(context.request.path, "original")
        XCTAssertEqual(context.urlRequest.url?.path, "/mutated")
        XCTAssertEqual(context.urlRequest.value(forHTTPHeaderField: "X-Mutated"), "yes")
    }

    func testRequestInterceptorReturnSkipsRemainingInterceptorsAndTransport() async throws {
        let recorder = CorePipelineRecorder()
        URLProtocolStub.setObserver { _ in recorder.recordTransport() }
        let api = CoreAPI(
            requestInterceptors: [
                ReturningRequestInterceptor(recorder: recorder),
                CountingRequestInterceptor(recorder: recorder),
            ]
        )

        let response = try await api.response(for: EmptyPathCoreRequest())

        XCTAssertEqual(response, CoreResponse(someValue: "mocked"))
        XCTAssertEqual(recorder.returningRequestInterceptorCount, 1)
        XCTAssertEqual(recorder.laterRequestInterceptorCount, 0)
        XCTAssertEqual(recorder.transportCount, 0)
    }

    func testRequestRestartRebuildsRequestAndSkipsFirstTransport() async throws {
        let recorder = CorePipelineRecorder()
        URLProtocolStub.setObserver { _ in recorder.recordTransport() }
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/items")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Discarded"))
            return .json(#"{"someValue":"restarted"}"#)
        }
        let api = CoreAPI(
            requestInterceptors: [
                MutateThenRestartRequestInterceptor(recorder: recorder),
            ]
        )

        let response = try await api.response(
            for: ExplicitCoreRequest(path: "items")
        )

        XCTAssertEqual(response, CoreResponse(someValue: "restarted"))
        XCTAssertEqual(recorder.restartingRequestInterceptorCount, 2)
        XCTAssertEqual(recorder.transportCount, 1)
    }

    func testResponseRestartSkipsRemainingInterceptorsAndRerunsFullPipeline() async throws {
        let recorder = CorePipelineRecorder()
        URLProtocolStub.setObserver { _ in recorder.recordTransport() }
        URLProtocolStub.setHandler { _ in
            .json(#"{"someValue":"response"}"#)
        }
        let api = CoreAPI(
            requestInterceptors: [
                CountingEveryRequestInterceptor(recorder: recorder),
            ],
            responseInterceptors: [
                RestartOnceResponseInterceptor(recorder: recorder),
                CountingResponseInterceptor(recorder: recorder),
            ]
        )

        let response = try await api.response(for: EmptyPathCoreRequest())

        XCTAssertEqual(response, CoreResponse(someValue: "response"))
        XCTAssertEqual(recorder.everyRequestInterceptorCount, 2)
        XCTAssertEqual(recorder.restartingResponseInterceptorCount, 2)
        XCTAssertEqual(recorder.laterResponseInterceptorCount, 1)
        XCTAssertEqual(recorder.transportCount, 2)
    }

    func testResponseInterceptorCanTurnSuccessIntoFailure() async throws {
        URLProtocolStub.setHandler { _ in
            .json(#"{"someValue":"network"}"#)
        }
        let api = CoreAPI(
            responseInterceptors: [
                ReplacingStatusResponseInterceptor(statusCode: 503),
            ]
        )

        do {
            _ = try await api.response(for: EmptyPathCoreRequest())
            XCTFail("Expected interceptor-produced failure")
        } catch {
            guard case BifrostError.unsuccessfulStatusCode(let statusCode) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(statusCode, 503)
        }
    }
}

private protocol CoreMethod: Sendable {
    static var value: HTTPMethod { get }
}

private enum PostMethod: CoreMethod {
    static var value: HTTPMethod { .post }
}

private enum PutMethod: CoreMethod {
    static var value: HTTPMethod { .put }
}

private enum PatchMethod: CoreMethod {
    static var value: HTTPMethod { .patch }
}

private enum DeleteMethod: CoreMethod {
    static var value: HTTPMethod { .delete }
}

private struct CoreResponse: Codable, Equatable {
    let someValue: String
}

private struct DictionaryPayload: Encodable {
    let createdAt: Date
    let rawData: Data
    let floatingPoint: Double
    let tags: [String]
    let optional: String?
}

private struct MinimalCoreAPI: API {
    let baseURL = URL(string: "https://example.com/api")!
}

private struct CoreAPI: API {
    let baseURL: URL
    let session: URLSession
    let queryItems: [URLQueryItem]
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let requestInterceptors: [any RequestInterceptor]
    let responseInterceptors: [any ResponseInterceptor]

    init(
        baseURL: URL = URL(string: "https://example.com/api")!,
        session: URLSession = makeURLSession(),
        queryItems: [URLQueryItem] = [],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        requestInterceptors: [any RequestInterceptor] = [],
        responseInterceptors: [any ResponseInterceptor] = []
    ) {
        self.baseURL = baseURL
        self.session = session
        self.queryItems = queryItems
        self.encoder = encoder
        self.decoder = decoder
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
    }

    var urlSession: URLSession { session }
    var jsonEncoder: JSONEncoder { encoder }
    var jsonDecoder: JSONDecoder { decoder }

    func queryParameters() -> [URLQueryItem] {
        queryItems
    }
}

private struct CoreQueryRequest: Requestable {
    let searchTerm: String
    let tags: [String]
    let optional: String?

    var path: String { "search" }

    typealias Response = CoreResponse
}

private struct CoreBodyRequest<Method: CoreMethod>: Requestable, Sendable {
    let someValue: String

    var path: String { "body" }
    var method: HTTPMethod { Method.value }

    typealias Response = CoreResponse
}

private struct ExplicitCoreRequest: Requestable {
    let path: String
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]

    var headerFields: [String: String] { headers }

    func queryParameters() throws -> [URLQueryItem] {
        queryItems
    }

    func encode(to encoder: any Encoder) throws {}

    typealias Response = CoreResponse
}

private struct EmptyPathCoreRequest: Requestable {
    var path: String { "" }

    typealias Response = CoreResponse
}

private struct EmptyCoreRequest: Requestable {
    var path: String { "empty" }

    typealias Response = EmptyResponse
}

private struct ThrowingQueryRequest: Requestable {
    var path: String { "query-error" }

    func encode(to encoder: any Encoder) throws {
        throw CoreTestError.encoding
    }

    typealias Response = CoreResponse
}

private struct ThrowingBodyRequest: Requestable {
    var path: String { "body-error" }
    var method: HTTPMethod { .post }

    func encode(to encoder: any Encoder) throws {
        throw CoreTestError.encoding
    }

    typealias Response = CoreResponse
}

private enum CoreTestError: Error, Equatable {
    case encoding
}

private final class CorePipelineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Int] = [:]

    var transportCount: Int { count(for: "transport") }
    var returningRequestInterceptorCount: Int { count(for: "request-return") }
    var laterRequestInterceptorCount: Int { count(for: "request-later") }
    var restartingRequestInterceptorCount: Int { count(for: "request-restart") }
    var everyRequestInterceptorCount: Int { count(for: "request-every") }
    var restartingResponseInterceptorCount: Int { count(for: "response-restart") }
    var laterResponseInterceptorCount: Int { count(for: "response-later") }

    func recordTransport() {
        record("transport")
    }

    func recordReturningRequestInterceptor() {
        record("request-return")
    }

    func recordLaterRequestInterceptor() {
        record("request-later")
    }

    func recordRestartingRequestInterceptor() -> Int {
        record("request-restart")
    }

    func recordEveryRequestInterceptor() {
        record("request-every")
    }

    func recordRestartingResponseInterceptor() -> Int {
        record("response-restart")
    }

    func recordLaterResponseInterceptor() {
        record("response-later")
    }

    @discardableResult
    private func record(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage[key, default: 0] += 1
        return storage[key, default: 0]
    }

    private func count(for key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage[key, default: 0]
    }
}

private struct ReturningRequestInterceptor: RequestInterceptor {
    let recorder: CorePipelineRecorder

    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request: Requestable {
        recorder.recordReturningRequestInterceptor()

        return .return(
            InterceptedResponse(
                body: try JSONEncoder().encode(CoreResponse(someValue: "mocked")),
                httpResponse: HTTPURLResponse(
                    url: context.urlRequest.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        )
    }
}

private struct CountingRequestInterceptor: RequestInterceptor {
    let recorder: CorePipelineRecorder

    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request: Requestable {
        recorder.recordLaterRequestInterceptor()
        return .continue
    }
}

private struct MutateThenRestartRequestInterceptor: RequestInterceptor {
    let recorder: CorePipelineRecorder

    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request: Requestable {
        let invocation = recorder.recordRestartingRequestInterceptor()

        if invocation == 1 {
            context.urlRequest.url = URL(string: "https://discarded.example.com/mutated")
            context.urlRequest.setValue("yes", forHTTPHeaderField: "X-Discarded")
            return .restart
        }

        XCTAssertEqual(context.urlRequest.url?.absoluteString, "https://example.com/api/items")
        XCTAssertNil(context.urlRequest.value(forHTTPHeaderField: "X-Discarded"))
        return .continue
    }
}

private struct CountingEveryRequestInterceptor: RequestInterceptor {
    let recorder: CorePipelineRecorder

    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request: Requestable {
        recorder.recordEveryRequestInterceptor()
        return .continue
    }
}

private struct RestartOnceResponseInterceptor: ResponseInterceptor {
    let recorder: CorePipelineRecorder

    func intercept(
        _ response: inout InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        let invocation = recorder.recordRestartingResponseInterceptor()
        return invocation == 1 ? .restart : .continue
    }
}

private struct CountingResponseInterceptor: ResponseInterceptor {
    let recorder: CorePipelineRecorder

    func intercept(
        _ response: inout InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        recorder.recordLaterResponseInterceptor()
        return .continue
    }
}

private struct ReplacingStatusResponseInterceptor: ResponseInterceptor {
    let statusCode: Int

    func intercept(
        _ response: inout InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        response.httpResponse = HTTPURLResponse(
            url: response.httpResponse.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: response.headerFields
        )!
        return .continue
    }
}

private final class NonHTTPResponseURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = URLResponse(
            url: request.url!,
            mimeType: "application/json",
            expectedContentLength: 23,
            textEncodingName: "utf-8"
        )
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"someValue":"value"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeNonHTTPURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NonHTTPResponseURLProtocol.self]
    return URLSession(configuration: configuration)
}

@MainActor
private func assertDefaultBodyRequest<Method>(
    _ request: CoreBodyRequest<Method>,
    expectedMethod: String
) async throws where Method: CoreMethod {
    URLProtocolStub.setHandler { urlRequest in
        XCTAssertEqual(urlRequest.httpMethod, expectedMethod)
        XCTAssertNil(urlRequest.url?.query)

        let body = try XCTUnwrap(requestBodyData(from: urlRequest))
        let decoded = try JSONDecoder().decode(CoreResponse.self, from: body)
        XCTAssertEqual(decoded, CoreResponse(someValue: request.someValue))

        return .json(#"{"someValue":"response"}"#)
    }

    let response = try await CoreAPI().response(for: request)
    XCTAssertEqual(response, CoreResponse(someValue: "response"))
}

private extension StubbedResponse {
    static func json(
        _ body: String,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) -> Self {
        Self(body: body, statusCode: statusCode, headers: headers)
    }
}
