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

/// The result of an interceptor invocation.
///
/// Each case controls the remainder of the request or response interception
/// phase. The contained value is an ``InterceptedResponse`` in Bifrost's
/// built-in pipeline.
public enum InterceptionResult<Value> {
    /// Continues with the next interceptor or the next pipeline stage.
    ///
    /// Mutations made through the interceptor's `inout` argument remain in
    /// effect.
    case `continue`

    /// Stops the current phase and uses the provided value.
    ///
    /// From a request interceptor, this skips the remaining request interceptors
    /// and transport, then sends the value through response interception. From a
    /// response interceptor, this skips the remaining response interceptors. The
    /// resulting response is still subject to status validation and decoding.
    case `return`(Value)

    /// Abandons the current attempt and rebuilds the pipeline from the original request.
    ///
    /// Mutations to the current request or response value are discarded.
    /// External side effects performed by an interceptor remain in effect.
    /// Bifrost does not impose a restart limit.
    case restart
}

extension InterceptionResult: Sendable where Value: Sendable {}

/// A response container used while the interception pipeline is executing.
///
/// Interceptors can mutate the raw body or replace the HTTP response before
/// Bifrost validates the status code and decodes the body.
public struct InterceptedResponse: Sendable {
    /// The raw bytes that will be decoded if the response status is accepted.
    public var body: Data

    /// The HTTP metadata used for status validation and header access.
    public var httpResponse: HTTPURLResponse

    /// The status code read from ``httpResponse``.
    public var statusCode: Int { httpResponse.statusCode }

    /// The HTTP headers represented as string keys and values.
    ///
    /// Header entries with non-string keys are omitted. Other values are
    /// converted with `String(describing:)`.
    public var headerFields: [String: String] {
        Dictionary(
            uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value in
                guard let key = key as? String else {
                    return nil
                }

                return (key, String(describing: value))
            }
        )
    }

    /// Creates an intercepted response from a raw body and its HTTP metadata.
    ///
    /// - Parameters:
    ///   - body: The raw response body.
    ///   - httpResponse: The HTTP response metadata associated with that body.
    public init(body: Data, httpResponse: HTTPURLResponse) {
        self.body = body
        self.httpResponse = httpResponse
    }
}

/// A context passed through request interception.
///
/// The typed request remains available for request-specific decisions. The
/// built `URLRequest` is mutable and becomes the transport request if
/// interception continues.
public struct InterceptionContext<Request: Requestable>: Sendable {
    /// The typed request value from which the URL request was built.
    public let request: Request

    /// The authoritative request that will be sent if interception reaches transport.
    ///
    /// A pipeline restart discards mutations to this value and builds a new
    /// request from ``request``.
    public var urlRequest: URLRequest

    init(request: Request, urlRequest: URLRequest) {
        self.request = request
        self.urlRequest = urlRequest
    }
}

/// An object that can inspect or mutate a built `URLRequest` before transport.
///
/// Request interceptors run in ``API/requestInterceptors`` order after Bifrost
/// applies the request path, method, query, body, and headers. The generic
/// ``intercept(_:)`` method is called for every ``Requestable`` type, so an
/// interceptor can inspect `context.request` when behavior applies only to
/// selected request models.
///
/// Interceptors are `Sendable` because an ``API`` can be shared across
/// isolation domains. Immutable value types satisfy this requirement directly.
/// An interceptor with mutable reference state should isolate that state in an
/// actor or provide its own synchronization with a documented safety invariant
/// for its `@unchecked Sendable` conformance.
public protocol RequestInterceptor: Sendable {
    /// Intercepts a request before transport.
    ///
    /// - Parameter context: The typed request and mutable URL request for the
    ///   current attempt.
    /// - Returns: How Bifrost should continue the interception pipeline.
    /// - Throws: Any error that should stop the request.
    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request: Requestable
}

/// An object that can inspect or mutate a raw response and its HTTP metadata.
///
/// Response interceptors run in ``API/responseInterceptors`` order after
/// transport succeeds or a request interceptor supplies a response. They run
/// before status validation and decoding, which allows an interceptor to
/// recover from an otherwise unsuccessful HTTP status. Transport errors do not
/// produce an ``InterceptedResponse`` and therefore bypass this phase.
///
/// Interceptors are `Sendable` because an ``API`` can be shared across
/// isolation domains. Immutable value types satisfy this requirement directly.
/// An interceptor with mutable reference state should isolate that state in an
/// actor or provide its own synchronization with a documented safety invariant
/// for its `@unchecked Sendable` conformance.
public protocol ResponseInterceptor: Sendable {
    /// Intercepts a response before status validation and decoding.
    ///
    /// - Parameter response: The mutable raw body and HTTP metadata for the
    ///   current attempt.
    /// - Returns: How Bifrost should continue the interception pipeline.
    /// - Throws: Any error that should stop the request.
    func intercept(
        _ response: inout InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse>
}
