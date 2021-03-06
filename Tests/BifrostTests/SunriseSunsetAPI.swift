//
//  SunriseSunsetAPI.swift
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
import Bifrost

struct SunriseSunsetAPI: API {
    let baseURL: URL = URL(string: "https://api.sunrise-sunset.org/")!

    var dictionaryEncoder: DictionaryEncoder = {
        let de = DictionaryEncoder()
        de.keyEncodingStrategy = .convertToSnakeCase
        return de
    }()
    
    var jsonDecoder: JSONDecoder = {
        let jd = JSONDecoder()
        jd.dateDecodingStrategy = .iso8601
        jd.keyDecodingStrategy = .convertFromSnakeCase
        return jd
    }()
}

// Requests, Models

struct Request {
	private(set) var latitude: String
	private(set) var longitude: String
	private(set) var date: Date?
	private(set) var formatted: Bool = false

	enum CodingKeys: String, CodingKey {
		case latitude = "lat"
		case longitude = "lng"
		case date
		case formatted
	}
}

extension Request: Requestable {
    var path: String { "json" }

	struct Response: Decodable {
		let status: String
		let results: Results

		struct Results: Decodable {
			let sunrise: Date
			let sunset: Date
			let dayLength: TimeInterval
		}
	}
}
