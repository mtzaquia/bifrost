# Bifrost

Bifrost is a lightweight, scalable framework for interacting with JSON, REST APIs.

## Instalation

Bifrost is available via Swift Package Manager.

```swift
dependencies: [
  .package(url: "https://github.com/mtzaquia/bifrost.git", .upToNextMajor(from: "1.0.0")),
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
  func defaultParameters() -> [String : Any] {
    [
      "api-key": "<my secret key>"
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
  
  enum CodingKeys: String, CodingKey {
    case name
    case anotherParam = "another-param"
  }
}

extension MyRequest: Requestable {
  var path: String { "my-request.json" }
  
  struct Response: Decodable {
    let results: [MyResultObject]
  }
}
``` 

> **Note**
> If you expect an empty response, the built-in `EmptyResponse` type is avaiable for convenience.

### Making the call

Finally, you are ready to submit a request! Concurrency allows you to inline your call easily: 

```swift
// ...
let response = try await MyAPI.response(for: MyRequest(name: "My fancy name"))
print(response.results) // Our response is already a Swift type! More specifically, an instance of `MyRequest.Response`.
```

### Mocking

You may provide your own implementation of the `response(for:callback:)` function for mocking purposes:

```swift
struct MockedAPI: API {
  let baseURL: URL = URL(string: "foo://bar")!
    
  func response<Request>(
      for request: Request,
      additionalHeaderFields: [String: String],
      callback: @escaping (Result<Request.Response, Error>) -> Void
  ) where Request : Requestable {
      // my mocked implementation...
  }
}
```

## License

Copyright (c) 2021 @mtzaquia

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
