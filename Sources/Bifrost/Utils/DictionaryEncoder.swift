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

/// A JSON encoding configuration used by Bifrost's dictionary-backed query conversion.
///
/// The available strategies mirror `JSONEncoder`. Bifrost's default
/// ``Requestable/queryParameters()`` implementation owns its own encoder;
/// constructing or configuring another instance does not change global request
/// encoding.
public final class DictionaryEncoder: Sendable {
    /// Creates an encoder with the standard `JSONEncoder` strategies.
    public init() {}
    
	private let encoder = JSONEncoder()

    /// The strategy used to represent `Date` values.
	public var dateEncodingStrategy: JSONEncoder.DateEncodingStrategy {
		set { encoder.dateEncodingStrategy = newValue }
		get { encoder.dateEncodingStrategy }
	}
	
    /// The strategy used to represent `Data` values.
	public var dataEncodingStrategy: JSONEncoder.DataEncodingStrategy {
		set { encoder.dataEncodingStrategy = newValue }
		get { encoder.dataEncodingStrategy }
	}
	
    /// The strategy used to represent nonconforming floating-point values.
	public var nonConformingFloatEncodingStrategy: JSONEncoder.NonConformingFloatEncodingStrategy {
		set { encoder.nonConformingFloatEncodingStrategy = newValue }
		get { encoder.nonConformingFloatEncodingStrategy }
	}
	
    /// The strategy used to transform encoded keys.
	public var keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy {
		set { encoder.keyEncodingStrategy = newValue }
		get { encoder.keyEncodingStrategy }
	}
	
	func encode<T>(_ value: T) throws -> [String: Any] where T: Encodable {
        try JSONSerialization.jsonObject(
            with: try encoder.encode(value),
            options: .allowFragments
        ) as! [String: Any]
	}
}
