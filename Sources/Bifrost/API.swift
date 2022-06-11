//
//  API.swift
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
import Combine
import OSLog

private let defaultJSONDecoder = JSONDecoder()
private let defaultJSONEncoder = JSONEncoder()
private let defaultDictionaryEncoder = DictionaryEncoder()

public protocol API {
    /// The base URL from which requests will be made. _i.e.:_ https://api.myapp.com/
    var baseURL: URL { get }
    
    /// The session to the used for this API. The default implementation provides `.shared` as default.
    var urlSession: URLSession { get }
    
    /// The default query parameters that should always be added to requests on this particular API.
    func defaultQueryParameters() -> [String: Any]
    
    /// The default header fields that should always be added to requests on this particular API.
    func defaultHeaderFields() -> [String: String]
    
    /// The `DictionaryEncoder` instance that will encode your API request parameters.
    var dictionaryEncoder: DictionaryEncoder { get }
    
    /// The `JSONEncoder` instance that will encode your API request body.
    var jsonEncoder: JSONEncoder { get }
    
    /// The `JSONDecoder` instance that will decode your API responses.
    var jsonDecoder: JSONDecoder { get }
    
    /// Makes a specific request to the target API.
    /// This function has a default implementation which can be overridden, mostly for mocking purposes.
    /// - Parameters:
    ///   - request: The request to be used.
    ///   - callback: The callback with the request's `Result`.
    /// - Returns: A strongly-typed response from the API.
    func response<Request>(
        for request: Request,
        callback: @escaping (Result<Request.Response, Error>) -> Void
    ) where Request: Requestable
}

public extension API {
    var urlSession: URLSession { .shared }
    
    var dictionaryEncoder: DictionaryEncoder { defaultDictionaryEncoder }
    var jsonEncoder: JSONEncoder { defaultJSONEncoder }
    var jsonDecoder: JSONDecoder { defaultJSONDecoder }
    
    func defaultQueryParameters() -> [String: Any] { [:] }
    func defaultHeaderFields() -> [String: String] { [:] }
}

public extension API {
    func response<Request>(
        for request: Request,
        callback: @escaping (Result<Request.Response, Error>) -> Void
    ) where Request: Requestable {
        let initialURL = request.path.isEmpty
        ? baseURL
        : baseURL.appendingPathComponent(request.path)
        
        let requestURL: URL
        do {
            let requestParameters = try request.queryParameters(dictionaryEncoder)
            let allQueryParameters = requestParameters
                .merging(defaultQueryParameters(), uniquingKeysWith: { (current, _) in current })
            
            requestURL = try self.requestURL(for: initialURL, with: allQueryParameters)
        } catch {
            callback(.failure(error))
            return
        }
        
        Logger.bifrost.info("\(request.method.rawValue) request: \(requestURL.absoluteString)")
        
        let allHeaderFields = request.defaultHeaderFields
            .merging(defaultHeaderFields(), uniquingKeysWith: { (current, _) in current })
        
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = request.method.rawValue
        
        do {
            urlRequest.httpBody = try request.bodyParameters(jsonEncoder)
        } catch {
            callback(.failure(error))
            return
        }
        
        for (field, value) in allHeaderFields {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        
        Logger.bifrost.debug("Header fields: \(urlRequest.allHTTPHeaderFields ?? [:])")
        
        let task = urlSession.dataTask(with: urlRequest) { data, _, error in
            if let error = error {
                callback(.failure(error))
                return
            }
            
            guard let data = data else {
                callback(.failure(URLError(.cannotDecodeRawData)))
                return
            }
            
            Logger.bifrost.debug("\(String(data: data, encoding: .utf8) ?? "Unable to read response as JSON")")
            
            do {
                if Request.Response.self == EmptyResponse.self {
                    callback(.success(EmptyResponse() as! Request.Response))
                } else {
                    callback(.success(try jsonDecoder.decode(Request.Response.self, from: data)))
                }
            } catch {
                callback(.failure(error))
                return
            }
        }
        
        task.resume()
    }
}

public extension API {
    /// Returns a publisher for a given request.
    /// - Parameters:
    ///   - request: The request to be used.
    /// - Returns: A strongly-typed response from the API.
    func publisher<Request>(
        for request: Request
    ) -> AnyPublisher<Request.Response, Error> where Request: Requestable {
        Deferred {
            Future { promise in
                self.response(
                    for: request,
                    callback: promise
                )
            }
        }
        .eraseToAnyPublisher()
    }
}

@available(iOS 15, *)
public extension API {
    /// Makes a specific request to the target API asynchronously.
    /// - Parameters:
    ///   - request: The request to be used.
    /// - Returns: A strongly-typed response from the API.
    func response<Request>(
        for request: Request
    ) async throws -> Request.Response where Request: Requestable {
        try await withCheckedThrowingContinuation { continuation in
            response(
                for: request,
                callback: continuation.resume(with:)
            )
        }
    }
}

private extension API {
    func requestURL(for initialURL: URL, with parameters: [String: Any]) throws -> URL {
        guard var urlComponents = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        
        var queryItems: [URLQueryItem] = urlComponents.queryItems ?? []
        for (key, value) in parameters {
            queryItems.append(URLQueryItem(name: key, value: "\(value)"))
        }
        
        urlComponents.queryItems = queryItems
        guard let requestURL = urlComponents.url else {
            throw URLError(.badURL)
        }
        
        return requestURL
    }
}
