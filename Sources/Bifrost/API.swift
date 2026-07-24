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

import Foundation

private let defaultJSONDecoder = JSONDecoder()
private let defaultJSONEncoder = JSONEncoder()

private enum PipelineResult {
    case response(InterceptedResponse)
    case restart
}

/// A client configuration that builds, sends, and decodes typed HTTP requests.
///
/// Conforming types provide the service URL and can customize transport,
/// JSON coding, shared query parameters, and interception. Call
/// ``response(for:)`` with a ``Requestable`` value to execute a request.
public protocol API {
    /// The URL against which nonempty ``Requestable/path`` values are appended.
    ///
    /// Query items already present in this URL are preserved. An empty request
    /// path uses this URL without appending another path component.
    var baseURL: URL { get }
    
    /// The session that performs requests which reach transport.
    ///
    /// The default implementation returns `URLSession.shared`. Bifrost does not
    /// invalidate a custom session.
    var urlSession: URLSession { get }
    
    /// Returns query items to include in every request made by this API.
    ///
    /// Bifrost appends these items after query items from ``baseURL`` and before
    /// the items returned by ``Requestable/queryParameters()``. Duplicate names
    /// are preserved.
    ///
    /// - Returns: The API-wide query items, or an empty array by default.
    func queryParameters() -> [URLQueryItem]
    
    /// The encoder passed to ``Requestable/bodyParameters(_:)``.
    ///
    /// Override this property to configure the default JSON bodies for `POST`,
    /// `PUT`, and `PATCH` requests. It does not affect default `GET` query
    /// encoding.
    var jsonEncoder: JSONEncoder { get }
    
    /// The decoder used for the final successful response body.
    ///
    /// ``EmptyResponse`` bypasses decoding. All other response types are decoded
    /// only after response interception and status validation complete.
    var jsonDecoder: JSONDecoder { get }

    /// The interceptors applied after the `URLRequest` is built and before transport.
    ///
    /// Interceptors run in array order. They can mutate the authoritative request,
    /// provide an ``InterceptedResponse`` without using transport, or restart the
    /// pipeline. The default implementation returns an empty array.
    var requestInterceptors: [any RequestInterceptor] { get }

    /// The response interceptors applied after a raw response has been received or mocked.
    ///
    /// Interceptors run in array order before status validation and decoding. They
    /// can inspect or replace the body and HTTP metadata, return a final raw
    /// response, or restart the full pipeline. Transport failures do not enter this
    /// phase. The default implementation returns an empty array.
    var responseInterceptors: [any ResponseInterceptor] { get }
}

// MARK: - Defaults

public extension API {
    var urlSession: URLSession { .shared }

    func queryParameters() -> [URLQueryItem] { [] }

    var jsonEncoder: JSONEncoder { defaultJSONEncoder }
    var jsonDecoder: JSONDecoder { defaultJSONDecoder }

    var requestInterceptors: [any RequestInterceptor] { [] }
    var responseInterceptors: [any ResponseInterceptor] { [] }
}

// MARK: - Request

public extension API {
    /// Executes a request and decodes its typed response.
    ///
    /// Bifrost builds a fresh `URLRequest`, runs ``requestInterceptors``, uses
    /// ``urlSession`` unless an interceptor provides a response, and then runs
    /// ``responseInterceptors``. After interception, status codes from `200`
    /// through `399` are accepted and the body is decoded as
    /// ``Requestable/Response``. Any other status throws
    /// ``BifrostError/unsuccessfulStatusCode(_:)``.
    ///
    /// Returning ``InterceptionResult/restart`` abandons the current attempt and
    /// rebuilds the request from the original request value. Bifrost does not cap
    /// restart attempts, so a restarting interceptor must eventually allow the
    /// pipeline to continue or throw.
    ///
    /// - Parameter request: The request to perform.
    /// - Returns: The final decoded response body after all interceptors have run.
    /// - Throws: An error from request encoding, an interceptor, transport, status
    ///   validation, or response decoding. Cancellation errors are propagated.
    func response<Request>(
        for request: Request
    ) async throws -> Request.Response where Request: Requestable {
        try await BifrostLogTrace.withNewID {
            func executeRequest(attempt: Int) async throws -> PipelineResult {
                let requestURL = try buildURL(for: request)
                let requestForTask = try buildURLRequest(
                    for: request,
                    at: requestURL
                )

                var context = InterceptionContext(request: request, urlRequest: requestForTask)

                for (index, interceptor) in requestInterceptors.enumerated() {
                    bifrostLog.bifrostDebug(
                        .interceptorRunning(
                            phase: .request,
                            index: index + 1,
                            count: requestInterceptors.count,
                            type: String(describing: type(of: interceptor))
                        )
                    )

                    switch try await interceptor.intercept(&context) {
                    case .continue:
                        continue
                    case .return(let response):
                        logRequest(context.urlRequest, attempt: attempt)
                        logResponse(response, source: .requestInterceptor)
                        return .response(response)
                    case .restart:
                        logRequest(context.urlRequest, attempt: attempt)
                        return .restart
                    }
                }

                logRequest(context.urlRequest, attempt: attempt)
                let response = try await getResponse(for: context.urlRequest)
                logResponse(response, source: .transport)
                return .response(response)
            }

            func executeResponseInterceptors(
                _ response: InterceptedResponse
            ) async throws -> PipelineResult {
                var finalResponse = response

                for (index, interceptor) in responseInterceptors.enumerated() {
                    bifrostLog.bifrostDebug(
                        .interceptorRunning(
                            phase: .response,
                            index: index + 1,
                            count: responseInterceptors.count,
                            type: String(describing: type(of: interceptor))
                        )
                    )

                    switch try await interceptor.intercept(&finalResponse) {
                    case .continue:
                        continue
                    case .return(let response):
                        logResponse(response, source: .responseInterceptor)
                        return .response(response)
                    case .restart:
                        return .restart
                    }
                }

                return .response(finalResponse)
            }

            var attempt = 1

            do {
                while true {
                    let requestResult = try await executeRequest(attempt: attempt)

                    switch requestResult {
                    case .restart:
                        attempt += 1
                        bifrostLog.bifrostDebug(
                            .pipelineRestarted(phase: .request, nextAttempt: attempt)
                        )
                        continue
                    case .response(let response):
                        let responseResult = try await executeResponseInterceptors(response)

                        switch responseResult {
                        case .restart:
                            attempt += 1
                            bifrostLog.bifrostDebug(
                                .pipelineRestarted(phase: .response, nextAttempt: attempt)
                            )
                            continue
                        case .response(let response):
                            let decoded = try decodeResponse(response, as: Request.Response.self)
                            bifrostLog.bifrostDebug(
                                .requestSucceeded(
                                    statusCode: response.statusCode,
                                    byteCount: response.body.count
                                )
                            )
                            return decoded
                        }
                    }
                }
            } catch let error as CancellationError {
                bifrostLog.bifrostDebug(.requestCancelled)
                throw error
            } catch let error as URLError where error.code == .cancelled {
                bifrostLog.bifrostDebug(.requestCancelled)
                throw error
            } catch {
                bifrostLog.bifrostDebug(.requestFailed(error: error))
                throw error
            }
        }
    }
}

private extension API {
    func decodeResponse<Response>(
        _ response: InterceptedResponse,
        as responseType: Response.Type
    ) throws -> Response where Response: Decodable {
        if !(200..<400).contains(response.statusCode) {
            throw BifrostError.unsuccessfulStatusCode(response.statusCode)
        }

        if responseType == EmptyResponse.self {
            return EmptyResponse() as! Response
        } else {
            return try jsonDecoder.decode(responseType, from: response.body)
        }
    }

    func getResponse(for request: URLRequest) async throws -> InterceptedResponse {
        try Task.checkCancellation()

        let (data, response) = try await urlSession.data(for: request)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return InterceptedResponse(body: data, httpResponse: httpResponse)
    }

    func logRequest(_ request: URLRequest, attempt: Int) {
#if DEBUG
        bifrostLog.bifrostDebug(
            .requestStarted(
                attempt: attempt,
                method: request.httpMethod ?? "GET",
                url: BifrostLogURL.normalDescription(for: request.url)
            )
        )
        bifrostLog.bifrostDebug(
            .requestURL(request.url?.absoluteString ?? "<missing URL>")
        )
        bifrostLog.bifrostDebug(
            .requestHeaders(request.allHTTPHeaderFields ?? [:])
        )

        if let body = request.httpBody {
            bifrostLog.bifrostDebug(
                .requestBody(
                    body: String(data: body, encoding: .utf8) ?? "<binary>",
                    byteCount: body.count
                )
            )
        }
#endif
    }

    func logResponse(_ response: InterceptedResponse, source: BifrostResponseSource) {
#if DEBUG
        bifrostLog.bifrostDebug(
            .responseReceived(
                source: source,
                statusCode: response.statusCode,
                byteCount: response.body.count
            )
        )
        bifrostLog.bifrostDebug(.responseHeaders(response.headerFields))
#endif
    }
}

private extension API {
    func buildURL<Request>(for request: Request) throws -> URL where Request: Requestable {
        let initialURL = request.path.isEmpty ? baseURL : baseURL.appendingPathComponent(request.path)

        guard var urlComponents = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        let queryItems = (urlComponents.queryItems ?? [])
            + queryParameters()
            + (try request.queryParameters())
        urlComponents.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let requestURL = urlComponents.url else {
            throw URLError(.badURL)
        }

        return requestURL
    }

    func buildURLRequest<Request>(
        for request: Request,
        at url: URL
    ) throws -> URLRequest where Request: Requestable {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        if let body = try request.bodyParameters(jsonEncoder) {
            urlRequest.httpBody = body
        }

        for (field, value) in request.headerFields {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        return urlRequest
    }
}
