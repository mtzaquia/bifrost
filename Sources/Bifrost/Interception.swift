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
/// Use ``continue`` to keep moving through the chain, or ``return(_:)`` to stop the
/// current phase early and provide the response that should be used from that point on.
public enum InterceptionResult<Value> {
    /// Continue with the next interceptor or transport step.
    case `continue`
    /// Stop the current interceptor phase and use the provided value instead.
    case `return`(Value)
}

/// A response container used while the interception pipeline is executing.
///
/// It gives interceptors access to both the raw response body and the underlying
/// HTTP metadata associated with that response.
public struct InterceptedResponse {
    /// The raw response body.
    public var body: Data

    /// The underlying HTTP response metadata.
    public var httpResponse: HTTPURLResponse

    /// The HTTP status code of the response.
    public var statusCode: Int { httpResponse.statusCode }

    /// The HTTP headers normalized into a string dictionary.
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
/// The original request model is read-only. The built ``URLRequest`` is mutable and is the
/// authoritative request that will be sent if the chain continues to transport.
public struct InterceptionContext<Request: Requestable> {
    /// The original request model used to build the ``urlRequest``.
    public let request: Request

    /// The built request that will be sent if interception continues to transport.
    public var urlRequest: URLRequest

    init(request: Request, urlRequest: URLRequest) {
        self.request = request
        self.urlRequest = urlRequest
    }
}

/// An object that can inspect or mutate a built ``URLRequest`` before transport.
///
/// Request interceptors run in order after Bifrost has built the final ``URLRequest`` from the
/// request model. They receive an ``InterceptionContext`` by `inout`, which lets them inspect
/// the original request and mutate the authoritative ``URLRequest`` before it is sent. Returning
/// ``InterceptionResult/continue`` passes execution to the next request interceptor. Returning
/// ``InterceptionResult/return(_:)`` short-circuits transport and provides a raw mocked or
/// recovered response that will be passed to response interceptors.
public protocol RequestInterceptor {
    /// Intercepts a request before transport.
    ///
    /// - Parameter context: The request interception context containing the original request and built ``URLRequest``.
    /// - Returns: Whether the request phase should continue or short-circuit with a response.
    func intercept<Request>(
        _ context: inout InterceptionContext<Request>
    ) async throws -> InterceptionResult<InterceptedResponse> where Request: Requestable
}

/// An object that can inspect or mutate a raw response and its HTTP metadata.
///
/// Response interceptors run in order after transport succeeds or a request interceptor short-circuits.
/// They receive an ``InterceptedResponse`` containing raw response data by `inout`, allowing them
/// to update the body bytes, replace the HTTP metadata, or both. A retry closure is provided so interceptors can rerun the
/// original request pipeline after performing recovery work. Returning
/// ``InterceptionResult/continue`` passes execution to the next response interceptor. Returning
/// ``InterceptionResult/return(_:)`` stops the response phase early and returns the supplied
/// response to the caller.
public protocol ResponseInterceptor {
    /// Intercepts a response before the final response body is returned to the caller.
    ///
    /// - Parameter response: The mutable intercepted response, including raw body data and HTTP metadata.
    /// - Parameter retry: Reruns the original request pipeline and returns a fresh intercepted response.
    /// - Returns: Whether the response phase should continue or stop early with a replacement response.
    func intercept(
        _ response: inout InterceptedResponse,
        retry: () async throws -> InterceptedResponse
    ) async throws -> InterceptionResult<InterceptedResponse>
}
