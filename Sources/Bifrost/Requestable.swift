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

private let defaultDictionaryEncoder = DictionaryEncoder()

/// An HTTP method supported by Bifrost's default request encoding.
public enum HTTPMethod: String {
    /// Retrieves a resource and encodes request properties as query items by default.
    case get = "GET"

    /// Creates a resource and encodes the request as a JSON body by default.
    case post = "POST"

    /// Replaces a resource and encodes the request as a JSON body by default.
    case put = "PUT"

    /// Partially updates a resource and encodes the request as a JSON body by default.
    case patch = "PATCH"

    /// Deletes a resource and sends neither query parameters nor a body by default.
    case delete = "DELETE"
}

/// A response type for accepted HTTP responses whose body should be ignored.
///
/// When this is a request's ``Requestable/Response``, Bifrost still runs
/// response interceptors and validates the status code, but it does not decode
/// the response bytes.
public struct EmptyResponse: Decodable {}

/// A typed description of an HTTP request and its decoded response.
///
/// Conforming values are `Encodable` because the default implementations derive
/// query items or a JSON body from the request's encoded properties.
public protocol Requestable: Encodable {
    /// The type decoded after response interception and status validation.
    associatedtype Response: Decodable
    
    /// The path component appended to ``API/baseURL``.
    ///
    /// Return an empty string to use the base URL unchanged. If a request
    /// property appears in the path of a `GET` request and should not also
    /// appear in its query, override ``queryParameters()``.
    var path: String { get }
    
    /// The HTTP method used for the request.
    ///
    /// The default implementation returns ``HTTPMethod/get``.
    var method: HTTPMethod { get }
    
    /// The HTTP header fields applied to this request before request interception.
    ///
    /// The default implementation returns an empty dictionary. Bifrost does not
    /// add a `Content-Type` header automatically, and a request interceptor can
    /// replace values supplied here.
    var headerFields: [String: String] { get }
    
    /// Returns the query items appended after the API-wide query items.
    ///
    /// For `GET`, the default implementation encodes a keyed request value and
    /// emits one query item per scalar value and repeated items for array
    /// values. Properties encoded as `nil` are omitted. A request must encode as
    /// a keyed JSON object to use this default. Other methods return no query
    /// items by default.
    ///
    /// - Returns: The query parameters to be appended to the request URL.
    /// - Throws: An error raised while encoding the request.
    func queryParameters() throws -> [URLQueryItem]

    /// Returns the bytes to use as the HTTP request body.
    ///
    /// The default implementation encodes the complete request value as JSON
    /// for `POST`, `PUT`, and `PATCH`. It returns `nil` for `GET` and `DELETE`.
    /// Override this method to use another mapping.
    ///
    /// - Parameter encoder: The encoder supplied by ``API/jsonEncoder``.
    /// - Returns: The request body, or `nil` to send no body.
    /// - Throws: An error raised while encoding the request.
    func bodyParameters(_ encoder: JSONEncoder) throws -> Data?
}

public extension Requestable {
    var method: HTTPMethod { .get }
    var headerFields: [String: String] { [:] }
    
    func queryParameters() throws -> [URLQueryItem] {
        if method == .get {
            let dict = try defaultDictionaryEncoder.encode(self)
            return dict.flatMap { (key, value) -> [URLQueryItem] in
                if let array = value as? [Any] {
                    return array.map { URLQueryItem(name: key, value: "\($0)") }
                } else {
                    return [URLQueryItem(name: key, value: "\(value)")]
                }
            }
        } else {
            return []
        }
    }
    
    func bodyParameters(_ encoder: JSONEncoder) throws -> Data? {
        if [HTTPMethod.post, .put, .patch].contains(method) {
            return try encoder.encode(self)
        } else {
            return nil
        }
    }
}
