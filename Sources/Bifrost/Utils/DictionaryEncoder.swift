//
//  DictionaryEncoder.swift
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

public class DictionaryEncoder {
	private let encoder = JSONEncoder()
	public var dateEncodingStrategy: JSONEncoder.DateEncodingStrategy {
		set { encoder.dateEncodingStrategy = newValue }
		get { encoder.dateEncodingStrategy }
	}
	
	public var dataEncodingStrategy: JSONEncoder.DataEncodingStrategy {
		set { encoder.dataEncodingStrategy = newValue }
		get { encoder.dataEncodingStrategy }
	}
	
	public var nonConformingFloatEncodingStrategy: JSONEncoder.NonConformingFloatEncodingStrategy {
		set { encoder.nonConformingFloatEncodingStrategy = newValue }
		get { encoder.nonConformingFloatEncodingStrategy }
	}
	
	public var keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy {
		set { encoder.keyEncodingStrategy = newValue }
		get { encoder.keyEncodingStrategy }
	}
	
	func encode<T>(_ value: T) throws -> [String: Any] where T : Encodable {
		try JSONSerialization.jsonObject(with: try encoder.encode(value),
										 options: .allowFragments) as! [String: Any]
	}
}
