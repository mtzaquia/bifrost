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
import OSLog

private let defaultJSONDecoder = JSONDecoder()
private let defaultJSONEncoder = JSONEncoder()

public protocol API {
    /// The base URL from which requests will be made. _i.e.:_ https://api.myapp.com/
    var baseURL: URL { get }
    
    /// The session to the used for this API. The default implementation provides `.shared` as default.
    var urlSession: URLSession { get }
    
    /// The default header fields that should always be added to requests on this particular API.
    ///
    /// - Parameter body: The body for the request about to be submitted.
    /// - Returns: The headers that are to be included with all the requests for this particular **API**.
    func headerFields(body: Data?) -> [String: String]

    /// The default query parameters that should always be added to requests on this particular API.
    func queryParameters() -> [URLQueryItem]
    
    /// The `JSONEncoder` instance that will encode your API request body.
    var jsonEncoder: JSONEncoder { get }
    
    /// The `JSONDecoder` instance that will decode your API responses.
    var jsonDecoder: JSONDecoder { get }

    /// The request interceptors applied before the final ``URLRequest`` is built.
    ///
    /// These interceptors run in array order and can either continue the pipeline or
    /// short-circuit transport by returning an ``InterceptedResponse``.
    var requestInterceptors: [any RequestInterceptor] { get }

    /// The response interceptors applied after a response has been decoded or mocked.
    ///
    /// These interceptors run in array order and can inspect or mutate the decoded body,
    /// status code, and headers before the final response body is returned.
    var responseInterceptors: [any ResponseInterceptor] { get }
}

// MARK: - Defaults

public extension API {
    var urlSession: URLSession { .shared }

    func headerFields(body: Data?) -> [String: String] { [:] }
    func queryParameters() -> [URLQueryItem] { [] }

    var jsonEncoder: JSONEncoder { defaultJSONEncoder }
    var jsonDecoder: JSONDecoder { defaultJSONDecoder }

    var requestInterceptors: [any RequestInterceptor] { [] }
    var responseInterceptors: [any ResponseInterceptor] { [] }
}

// MARK: - Request

public extension API {
    /// Makes a specific request to the target API.
    ///
    /// The request is first passed through ``requestInterceptors``. If none of them short-circuit,
    /// Bifrost builds the ``URLRequest`` and performs the network call internally. The resulting
    /// response, whether network-backed or mocked, is then passed through ``responseInterceptors``.
    /// Unsuccessful HTTP status codes are surfaced only after the response phase completes, which
    /// allows response interceptors to recover and retry.
    ///
    /// - Parameter request: The request to perform.
    /// - Returns: The final decoded response body after all interceptors have run.
    func response<Request>(
        for request: Request
    ) async throws -> Request.Response where Request: Requestable {
        func executeRequest() async throws -> InterceptedResponse<Request.Response> {
            var interceptedRequest = request
            var interceptedResponse: InterceptedResponse<Request.Response>?

            for interceptor in requestInterceptors where interceptedResponse == nil {
                switch try await interceptor.intercept(&interceptedRequest) {
                case .continue:
                    continue
                case .return(let response):
                    interceptedResponse = response
                }
            }

            if let interceptedResponse {
                return interceptedResponse
            } else {
                return try await performResponse(for: interceptedRequest)
            }
        }

        var finalResponse = try await executeRequest()

        for interceptor in responseInterceptors {
            switch try await interceptor.intercept(&finalResponse, retry: executeRequest) {
            case .continue:
                continue
            case .return(let response):
                return try handleResponse(response)
            }
        }

        return try handleResponse(finalResponse)
    }
}

private extension API {
    func handleResponse<Response>(
        _ response: InterceptedResponse<Response>
    ) throws -> Response {
        if !(200..<400).contains(response.statusCode) {
            throw BifrostError.unsuccessfulStatusCode(response.statusCode)
        }

        return response.body
    }

    func performResponse<Request>(
        for request: Request
    ) async throws -> InterceptedResponse<Request.Response> where Request: Requestable {
        let isDebugLoggingEnabled = await BifrostLogging.isDebugLoggingEnabled

        let requestURL = try buildURL(for: request)

        Logger.bifrost.info("❄ \(request.method.rawValue) \(requestURL.absoluteString)")

        let requestForTask = try buildURLRequest(
            for: request,
            at: requestURL,
            isDebugLoggingEnabled: isDebugLoggingEnabled
        )

        try Task.checkCancellation()

        let (data, response) = try await urlSession.data(for: requestForTask)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if isDebugLoggingEnabled {
            let code = httpResponse.statusCode
            let headers = httpResponse.allHeaderFields
            Logger.bifrost.debug("├ response: \(code)\n| \(headers.prettyPrinted(separator: "\n| "))")
        }

        if Request.Response.self == EmptyResponse.self {
            return InterceptedResponse(
                body: EmptyResponse() as! Request.Response,
                httpResponse: httpResponse
            )
        } else {
            return InterceptedResponse(
                body: try jsonDecoder.decode(Request.Response.self, from: data),
                httpResponse: httpResponse
            )
        }
    }
}

private extension API {
    func buildURL<Request>(for request: Request) throws -> URL where Request: Requestable {
        let initialURL = request.path.isEmpty ? baseURL : baseURL.appendingPathComponent(request.path)

        guard var urlComponents = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        urlComponents.queryItems = (urlComponents.queryItems ?? []) + queryParameters() + (try request.queryParameters())

        guard let requestURL = urlComponents.url else {
            throw URLError(.badURL)
        }

        return requestURL
    }

    func buildURLRequest<Request>(
        for request: Request,
        at url: URL,
        isDebugLoggingEnabled: Bool
    ) throws -> URLRequest where Request: Requestable {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        if let body = try request.bodyParameters(jsonEncoder) {
            urlRequest.httpBody = body

            if isDebugLoggingEnabled {
                let bodyString = String(data: body, encoding: .utf8)
                Logger.bifrost.debug("├ body: \(String(describing: bodyString))")
            }
        }

        let allHeaderFields = headerFields(body: urlRequest.httpBody)
            .merging(request.headerFields, uniquingKeysWith: { (_, new) in new })

        for (field, value) in allHeaderFields {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        if isDebugLoggingEnabled {
            Logger.bifrost.debug("├ header fields: \(urlRequest.allHTTPHeaderFields ?? [:])")
        }

        return urlRequest
    }
}
