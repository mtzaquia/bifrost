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
import OSLog

public protocol API {
    /// The base URL from which requests will be made. _i.e.:_ https://api.myapp.com/
    static var baseURL: String { get }
    
    /// The default query parameters that should always be added to requests on this particular API.
    static var defaultQueryParameters: [String: Any] { get }
    
    /// The default header fields that should always be added to requests on this particular API.
    static var defaultHeaderFields: [String: String] { get }
    
    /// A function allowing you to customise the `DictionaryEncoder` instance that will encode your API request parameters.
    /// - Parameter encoder: The encoder being used for building the request parameters.
    static func configureEncoder(_ encoder: inout DictionaryEncoder)
    
    /// A function allowing you to customise the `JSONDecoder` instance that will decode your API responses.
    /// - Parameter decoder: The decoder being used for processing the response.
    static func configureJSONDecoder(_ decoder: inout JSONDecoder)
    
    /// A function allowing you to customise the `JSONEncoder` instance that will encode your API request body.
    /// - Parameter encoder: The encoder being used for building the request body.
    static func configureJSONEncoder(_ encoder: inout JSONEncoder)
}

public extension API {
    static var defaultQueryParameters: [String: Any] { [:] }
    static var defaultHeaderFields: [String: String] { [:] }
    static func configureEncoder(_ encoder: inout DictionaryEncoder) {}
    static func configureJSONDecoder(_ decoder: inout JSONDecoder) {}
    static func configureJSONEncoder(_ encoder: inout JSONEncoder) {}
}

public extension API {
    /// Makes a specific request to the target API.
    /// - Parameters:
    ///   - request: The request to be used.
    ///   - session: The session to the used for this request. Defaults to `.shared`.
    ///   - callback: The callback with the request's `Result`.
    /// - Returns: A strongly-typed response from the API.
    static func response<Request>(
        for request: Request,
        session: URLSession = .shared,
        callback: @escaping (Result<Request.Response, Error>) -> Void
    ) where Request: Requestable {
        guard let initialURL = request.path.isEmpty
                ? URL(string: baseURL)
                : URL(string: baseURL)?.appendingPathComponent(request.path)
        else {
            callback(.failure(URLError(.badURL)))
            return
        }
        
        var dictEncoder = DictionaryEncoder()
        configureEncoder(&dictEncoder)
        
        let requestURL: URL
        do {
            let requestParameters = try request.queryParameters(dictEncoder)
            let allQueryParameters = requestParameters
                .merging(defaultQueryParameters, uniquingKeysWith: { (current, _) in current })
            
            requestURL = try self.requestURL(for: initialURL, with: allQueryParameters)
        } catch {
            callback(.failure(error))
            return
        }
        
        Logger.bifrost.info("\(request.method.rawValue) request: \(requestURL.absoluteString)")
        
        let allHeaderFields = request.defaultHeaderFields
            .merging(defaultHeaderFields, uniquingKeysWith: { (current, _) in current })
        
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = request.method.rawValue
        
        var jsonEncoder = JSONEncoder()
        configureJSONEncoder(&jsonEncoder)
        
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
        
        let task = session.dataTask(with: urlRequest) { data, _, error in
            if let error = error {
                callback(.failure(error))
                return
            }
            
            guard let data = data else {
                callback(.failure(URLError(.cannotDecodeRawData)))
                return
            }
            
            Logger.bifrost.debug("\(String(data: data, encoding: .utf8) ?? "Unable to read response as JSON")")
            
            var jsonDecoder = JSONDecoder()
            configureJSONDecoder(&jsonDecoder)
            
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

@available(iOS 15, *)
public extension API {
    /// Makes a specific request to the target API asynchronously.
    /// - Parameters:
    ///   - request: The request to be used.
    ///   - session: The session to the used for this request. Defaults to `.shared`.
    /// - Returns: A strongly-typed response from the API.
    static func response<Request>(
        for request: Request,
        session: URLSession = .shared
    ) async throws -> Request.Response where Request: Requestable {
        try await withCheckedThrowingContinuation { continuation in
            response(
                for: request,
                session: session,
                callback: continuation.resume(with:)
            )
        }
    }
}

private extension API {	
    static func requestURL(for initialURL: URL, with parameters: [String: Any]) throws -> URL {
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
