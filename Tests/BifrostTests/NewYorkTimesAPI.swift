//
//  NewYorkTimesAPI.swift
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

enum NewYorkTimesAPI: API {
	static let baseURL: String = "https://api.nytimes.com/svc/search/v2/"
	static var defaultQueryParameters: [String : Any] = [
		"api-key": "<...>"
	]
	
	static func configureJSONDecoder(_ decoder: inout JSONDecoder) {
		decoder.dateDecodingStrategy = .iso8601
	}
}

// Requests, Models

struct GenericResponse<Wrapped>: Decodable where Wrapped: Decodable {
	let status: String
	let response: Wrapped
}

struct ArticleSearchRequest {
	private(set) var query: String
	private(set) var filters: String?
	
	enum CodingKeys: String, CodingKey {
		case query = "q"
		case filters
	}
}

extension ArticleSearchRequest: Requestable {
	static var path: String = "articlesearch.json"
	
	typealias Response = GenericResponse<ArticleSearchResponse>
	struct ArticleSearchResponse: Decodable {
		let articles: [Article]
		
		enum CodingKeys: String, CodingKey {
			case articles = "docs"
		}
	}
}

struct Article: Decodable, Identifiable, Equatable {
	let abstract: String
	let webURL: String
	let leadParagraph: String
	let pubDate: Date
	let sectionName: String?
	let id: String
	
	enum CodingKeys: String, CodingKey {
		case abstract
		case webURL = "web_url"
		case leadParagraph = "lead_paragraph"
		case pubDate = "pub_date"
		case sectionName = "section_name"
		case id = "_id"
	}
}
