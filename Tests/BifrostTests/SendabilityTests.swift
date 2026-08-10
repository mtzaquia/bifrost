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
    func testConcurrencyContractsAreCheckedSendable() async throws {
        let requestInterceptor = ActorRequestInterceptor()
        let responseInterceptor = ActorResponseInterceptor()
        let api = SendableAPI(
            requestInterceptors: [requestInterceptor],
            responseInterceptors: [responseInterceptor]
        )
        let request = SendableRequest()
        var context = InterceptionContext(
            request: request,
            urlRequest: URLRequest(url: api.baseURL)
        )
        var response = InterceptedResponse(
            body: Data(),
            httpResponse: HTTPURLResponse(
                url: api.baseURL,
                statusCode: 204,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
        let result: InterceptionResult<InterceptedResponse> = .continue

        requireSendable(api)
        requireSendable(api as any API)
        requireSendable(api.requestInterceptors)
        requireSendable(api.responseInterceptors)
        requireSendable(request)
        requireSendable(SendableResponse())
        requireSendable(context)
        requireSendable(response)
        requireSendable(result)

        _ = try await requestInterceptor.intercept(&context)
        _ = try await responseInterceptor.intercept(&response)

        let requestInvocationCount = await requestInterceptor.invocationCount
        let responseInvocationCount = await responseInterceptor.invocationCount
        XCTAssertEqual(requestInvocationCount, 1)
        XCTAssertEqual(responseInvocationCount, 1)
    }
}

private func requireSendable<Value: Sendable>(_ value: Value) {}

private struct SendableAPI: API {
    let baseURL = URL(string: "https://example.com/api")!
    let requestInterceptors: [any RequestInterceptor]
    let responseInterceptors: [any ResponseInterceptor]
}

private struct SendableRequest: Requestable {
    var path: String { "sendable" }

    typealias Response = SendableResponse
}

private struct SendableResponse: Codable, Sendable {}

private actor ActorRequestInterceptor: RequestInterceptor {
    private(set) var invocationCount = 0

    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request: Requestable {
        invocationCount += 1
        return .continue
    }
}

private actor ActorResponseInterceptor: ResponseInterceptor {
    private(set) var invocationCount = 0

    func intercept(
        _ response: inout InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse> {
        invocationCount += 1
        return .continue
    }
}
