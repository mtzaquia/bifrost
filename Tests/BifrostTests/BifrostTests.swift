//
//  BifrostTests.swift
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

import XCTest
@testable import Bifrost

final class BifrostTests: XCTestCase {
	func testNewYorkTimes() {
		let expectation = XCTestExpectation()
		
		NewYorkTimesAPI.response(for: ArticleSearchRequest(query: "Test")) { result in
			switch result {
			case let .success(articles):
				XCTAssertNotNil(articles)
			case let .failure(error):
				XCTAssertNotNil(error)
			}
			
			expectation.fulfill()
		}
		
		wait(for: [expectation], timeout: 10)
	}
	
	func testSunsetSunrise() {
		let expectation = XCTestExpectation()

		SunriseSunsetAPI.response(for: Request(latitude: "36.7201600", longitude: "-4.4203400")) { result in
			switch result {
			case let .success(response):
				XCTAssertNotNil(response)
			case let .failure(error):
				XCTAssertNotNil(error)
			}

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 10)
	}
}
