//
//  DataAPI.swift
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

// API Declaration

struct DataAPI: API {
    let baseURL: URL = URL(string: "https://datausa.io/api/")!
    func defaultQueryParameters() -> [String : Any] {
        [
            "year": "latest"
        ]
    }
	
    var jsonDecoder: JSONDecoder = {
        let jd = JSONDecoder()
        jd.dateDecodingStrategy = .iso8601
        return jd
    }()
}

// Requests, Models

struct DataRequest {
	private(set) var drilldowns: String
	private(set) var measures: String
}

extension DataRequest: Requestable {
    typealias Response = DataResponse
    var path: String { "data" }
}

struct DataResponse: Decodable {
    let data: [DataEntry]
}

struct DataEntry: Decodable, Equatable {
    let idNation, nation: String
    let idYear: Int
    let year: String
    let population: Int
    let slugNation: String
    
    enum CodingKeys: String, CodingKey {
        case idNation = "ID Nation"
        case nation = "Nation"
        case idYear = "ID Year"
        case year = "Year"
        case population = "Population"
        case slugNation = "Slug Nation"
    }
}
