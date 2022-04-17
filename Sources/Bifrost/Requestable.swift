//
//  Requestable.swift
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

/// A type describing supported HTTP methods.
public enum HTTPMethod: String {
	case get = "GET"
	case post = "POST"
	case put = "PUT"
	case delete = "DELETE"
}

/// Use this type whenever the data response of your API is expected to be empty.
public struct EmptyResponse: Decodable {}

/// A protocol for a type that can make requests to an API.
public protocol Requestable: Encodable {
	/// The response type expected as a result from this request.
	associatedtype Response: Decodable

    /// The path for this request. This will be appended to the API's ``API/baseURL``. _i.e.:_ `"articleSearch.json"`.
    ///
    /// You may interpolate properties as needed in your path (_i.e.:_ `"/my-request/\(myId)"`).
    var path: String { get }

	/// The HTTP method to be used for this request. Defaults to ``HTTPMethod/get``.
	static var method: HTTPMethod { get }

	/// The default header fields that should always be added on this request.
	static var defaultHeaderFields: [String: String] { get }

	/// A function that provides the request parameters that should be part of the URL, as query parameters.
	///
	/// By default, all parameters are provided via query on ``HTTPMethod/get`` requests.
	/// You can override this function and provide a custom implementation.
	///
	/// - Parameter encoder: The dictionary encoder that should be used for building the result.
	/// - Returns: The query parameters to be appended to the request URL.
	func queryParameters(_ encoder: DictionaryEncoder) throws -> [String: Any]

	/// A function that provides the request parameters that should be part of the HTTP body.
	///
	/// By default, all parameters are provided via HTTP body on ``HTTPMethod/post`` requests.
	/// You can override this function and provide a custom implementation.
	///
	/// - Parameter encoder: The JSON encoder that should be used for building the result.
	/// - Returns: The HTTP body to be embeded with the request.
	func bodyParameters(_ encoder: JSONEncoder) throws -> Data?
}

public extension Requestable {
	static var method: HTTPMethod { .get }
	static var defaultHeaderFields: [String: String] { [:] }

	func queryParameters(_ encoder: DictionaryEncoder) throws -> [String: Any] {
		if Self.method == .get {
			return try encoder.encode(self)
		} else {
			return [:]
		}
	}

	func bodyParameters(_ encoder: JSONEncoder) throws -> Data? {
		if Self.method == .post {
			return try encoder.encode(self)
		} else {
			return nil
		}
	}
}
