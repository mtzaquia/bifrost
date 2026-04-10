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

private enum PipelineResult {
    case response(InterceptedResponse)
    case restart
}

public protocol API {
    /// The base URL from which requests will be made. _i.e.:_ https://api.myapp.com/
    var baseURL: URL { get }
    
    /// The session to the used for this API. The default implementation provides `.shared` as default.
    var urlSession: URLSession { get }
    
    /// The default query parameters that should always be added to requests on this particular API.
    func queryParameters() -> [URLQueryItem]
    
    /// The `JSONEncoder` instance that will encode your API request body.
    var jsonEncoder: JSONEncoder { get }
    
    /// The `JSONDecoder` instance that will decode your API responses.
    var jsonDecoder: JSONDecoder { get }

    /// The request interceptors applied after the final ``URLRequest`` is built and before transport.
    ///
    /// These interceptors run in array order and can either continue the pipeline or
    /// mutate the built ``URLRequest`` or short-circuit transport by returning an ``InterceptedResponse``.
    var requestInterceptors: [any RequestInterceptor] { get }

    /// The response interceptors applied after a raw response has been received or mocked.
    ///
    /// These interceptors run in array order and can inspect or mutate the raw body,
    /// status code, and headers before the final response body is returned.
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
    /// Makes a specific request to the target API.
    ///
    /// Bifrost first builds the ``URLRequest`` and passes it through ``requestInterceptors``.
    /// If none of them short-circuit, Bifrost performs the network call internally. The resulting raw
    /// response, whether network-backed or mocked, is then passed through ``responseInterceptors`` and
    /// decoded only after the response phase completes. Interceptors may return
    /// ``InterceptionResult/restart`` to restart the full request and response pipeline. Unsuccessful
    /// HTTP status codes are surfaced only after response interception, which allows recovery flows
    /// such as refresh-and-restart.
    ///
    /// - Parameter request: The request to perform.
    /// - Returns: The final decoded response body after all interceptors have run.
    func response<Request>(
        for request: Request
    ) async throws -> Request.Response where Request: Requestable {
        func executeRequest() async throws -> PipelineResult {
            let isDebugLoggingEnabled = await BifrostLogging.isDebugLoggingEnabled
            let requestURL = try buildURL(for: request)
            let requestForTask = try buildURLRequest(
                for: request,
                at: requestURL
            )

            var context = InterceptionContext(request: request, urlRequest: requestForTask)

            for interceptor in requestInterceptors {
                switch try await interceptor.intercept(&context) {
                case .continue:
                    continue
                case .return(let response):
                    return .response(response)
                case .restart:
                    return .restart
                }
            }

            let response = try await getResponse(
                for: context.urlRequest,
                isDebugLoggingEnabled: isDebugLoggingEnabled
            )
            return .response(response)
        }

        func executeResponseInterceptors(
            _ response: InterceptedResponse
        ) async throws -> PipelineResult {
            var finalResponse = response

            for interceptor in responseInterceptors {
                switch try await interceptor.intercept(&finalResponse) {
                case .continue:
                    continue
                case .return(let response):
                    return .response(response)
                case .restart:
                    return .restart
                }
            }

            return .response(finalResponse)
        }

        while true {
            let requestResult = try await executeRequest()

            switch requestResult {
            case .restart:
                continue
            case .response(let response):
                let responseResult = try await executeResponseInterceptors(response)

                switch responseResult {
                case .restart:
                    continue
                case .response(let response):
                    return try decodeResponse(response, as: Request.Response.self)
                }
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

    func getResponse(
        for request: URLRequest,
        isDebugLoggingEnabled: Bool
    ) async throws -> InterceptedResponse {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "<missing URL>"
        Logger.bifrost.info("❄ \(method) \(url)")

        if isDebugLoggingEnabled {
            if let body = request.httpBody {
                let bodyString = String(data: body, encoding: .utf8)
                Logger.bifrost.debug("├ body: \(String(describing: bodyString))")
            }

            Logger.bifrost.debug("├ header fields: \(request.allHTTPHeaderFields ?? [:])")
        }

        try Task.checkCancellation()

        let (data, response) = try await urlSession.data(for: request)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if isDebugLoggingEnabled {
            let code = httpResponse.statusCode
            let headers = httpResponse.allHeaderFields
            Logger.bifrost.debug("├ response: \(code)\n| \(headers.prettyPrinted(separator: "\n| "))")
        }

        return InterceptedResponse(body: data, httpResponse: httpResponse)
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
