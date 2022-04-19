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
	func testData() {
		let expectation = XCTestExpectation()
		
        DataAPI().response(for: DataRequest(drilldowns: "Nation", measures: "Population")) { result in
			switch result {
			case let .success(data):
				XCTAssertNotNil(data)
			case let .failure(error):
				XCTAssertNotNil(error)
			}
			
			expectation.fulfill()
		}
		
		wait(for: [expectation], timeout: 10)
	}

    @available(iOS 15, *)
    func testDataAsync() async throws {
        let data = try await DataAPI().response(for: DataRequest(drilldowns: "Nation", measures: "Population"))
        XCTAssertNotNil(data)
    }
	
	func testSunsetSunrise() {
		let expectation = XCTestExpectation()

		SunriseSunsetAPI().response(for: Request(latitude: "36.7201600", longitude: "-4.4203400")) { result in
			switch result {
			case let .success(response):
                    XCTAssertNotNil(response.results.sunrise)
                    XCTAssertNotNil(response.results.sunset)
                    XCTAssertNotNil(response.results.dayLength)
			case let .failure(error):
                    XCTAssertNotNil(error)
			}

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 10)
	}
}
