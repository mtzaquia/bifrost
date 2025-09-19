# Bifrost

Bifrost is a lightweight, scalable framework for interacting with JSON, REST APIs.

## Instalation

Bifrost is available via Swift Package Manager.

```swift
dependencies: [
  .package(url: "https://github.com/mtzaquia/bifrost.git", from: "2.0.0"),
],
```

## Usage

### API

Simply declare an entity conforming to `API` to start, then fulfill the required protocol conformances:

```swift
struct MyAPI: API {
  let baseURL: URL = URL(string: "https://api.myapi.com/v2/")!
  // ...
}
``` 

You can define default parameters and headers that will apply to all requests. You can also configure the decoder for your specific use-case.

```swift
struct MyAPI: API {
  // ...
  func queryParameters() -> [URLQueryItem]
    [
      URLQueryItem(name: "api-key", value: "<my secret key>")
    ]
  }

  var jsonDecoder: JSONDecoder = {
    let jd = JSONDecoder()
    jd.dateDecodingStrategy = .iso8601
    return jd
  }()
}
```

### Requests

For each request, create a type with its supported parameters. Make sure this type conforms to `Requestable`. 
You can also provide default header fields for a specific request if needed, and you can choose the HTTP method for that request. 

```swift
struct MyRequest {
  private(set) var name: String
  private(set) var anotherParam: String?
}

extension MyRequest: Requestable {
  var path: String { "api/my-request" }
  
  struct Response: Decodable {
    let results: [MyResultObject]
  }
}
``` 

> [!NOTE]
> If you expect an empty response, the built-in `EmptyResponse` type is avaiable for convenience.

### Making the call

Finally, you are ready to submit a request! Concurrency allows you to inline your call easily: 

```swift
// ...
let response = try await MyAPI.response(for: MyRequest(name: "My fancy name"))
print(response.results) // Our response is already a Swift type! More specifically, an instance of `MyRequest.Response`.
```

### Mocking, recovering

You may provide your own implementation of the `response(for:)` function for mocking purposes, or to handle recovery with custom logic:

```swift
struct MockedAPI: API {
  let baseURL: URL = URL(string: "foo://bar")!

  func response<Request>(
  for request: Request
  ) async throws -> Request.Response where Request : Requestable {
  do {
      return try await _response(for: request)
  } catch BifrostError.unsuccessfulStatusCode(404) {
      try await _response(for: TokenRefreshRequest())
  }
  return try await _response(for: request)
  }
}
```

## License

Copyright (c) 2025 @mtzaquia

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
