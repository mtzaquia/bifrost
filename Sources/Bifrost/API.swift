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
    /// - Returns: The headers that are to be included with all the requests for this particular API.
    func headerFields(body: Data?) -> [String: String]

    /// The default query parameters that should always be added to requests on this particular API.
    func queryParameters() -> [URLQueryItem]
    
    /// The `JSONEncoder` instance that will encode your API request body.
    var jsonEncoder: JSONEncoder { get }
    
    /// The `JSONDecoder` instance that will decode your API responses.
    var jsonDecoder: JSONDecoder { get }
    
    /// Makes a specific request to the target API.
    /// This function has a default implementation that can be overridden. This is useful for handling error codes in a bespoke way, or mocking responses.
    ///
    /// - Parameters:
    ///   - request: The request to be used.
    ///   - additionalHeaderFields: Extra header fields to be appended when executing the request. Useful for signed bodies, for instance.
    /// - Returns: A strongly-typed response from the API.
    func response<Request>(
        for request: Request,
        additionalHeaderFields: [String: String]
    ) async throws -> Request.Response where Request: Requestable
}

// MARK: - Defaults

public extension API {
    var urlSession: URLSession { .shared }

    func headerFields(body: Data?) -> [String: String] { [:] }
    func queryParameters() -> [URLQueryItem] { [] }

    var jsonEncoder: JSONEncoder { defaultJSONEncoder }
    var jsonDecoder: JSONDecoder { defaultJSONDecoder }
}

// MARK: - Request

public extension API {
    func response<Request>(
        for request: Request
    ) async throws -> Request.Response where Request: Requestable {
        try await response(for: request, additionalHeaderFields: [:])
    }

    func response<Request>(
        for request: Request,
        additionalHeaderFields: [String: String]
    ) async throws -> Request.Response where Request: Requestable {
        try await perform(request: request, additionalHeaderFields: additionalHeaderFields)
    }

    /// The default implementation for the API, which fetches data
    /// - Parameters:
    ///   - request: The request to be used.
    ///   - additionalHeaderFields: Extra header fields to be appended when executing the request. Useful for signed bodies, for instance.
    /// - Returns: A strongly-typed response from the API.
    func perform<Request>(
        request: Request,
        additionalHeaderFields: [String: String]
    ) async throws -> Request.Response where Request: Requestable {
        let isDebugLoggingEnabled = await BifrostLogging.isDebugLoggingEnabled

        let requestURL = try buildURL(for: request)

        Logger.bifrost.info("❄ \(request.method.rawValue) \(requestURL.absoluteString)")

        let requestForTask = try buildURLRequest(
            for: request,
            at: requestURL,
            additionalHeaderFields: additionalHeaderFields,
            isDebugLoggingEnabled: isDebugLoggingEnabled
        )

        try Task.checkCancellation()

        let (data, response) = try await urlSession.data(for: requestForTask)

        try Task.checkCancellation()

        if isDebugLoggingEnabled, let response = response as? HTTPURLResponse {
            let code = response.statusCode
            let headers = response.allHeaderFields
            Logger.bifrost.debug("├ response: \(code)\n| \(headers.prettyPrinted(separator: "\n| "))")
        }

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, !(200..<400).contains(statusCode) {
            throw BifrostError.unsuccessfulStatusCode(statusCode)
        }

        if Request.Response.self == EmptyResponse.self {
            return EmptyResponse() as! Request.Response
        } else {
            return try jsonDecoder.decode(Request.Response.self, from: data)
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
        additionalHeaderFields: [String: String],
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
            .merging(additionalHeaderFields, uniquingKeysWith: { (_, new) in new })

        for (field, value) in allHeaderFields {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        if isDebugLoggingEnabled {
            Logger.bifrost.debug("├ header fields: \(urlRequest.allHTTPHeaderFields ?? [:])")
        }

        return urlRequest
    }
}
