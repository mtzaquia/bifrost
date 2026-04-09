# Bifrost

Bifrost is a lightweight, scalable framework for interacting with JSON, REST APIs.

## Instalation

Bifrost is available via Swift Package Manager.

```swift
dependencies: [
  .package(url: "https://github.com/mtzaquia/bifrost.git", from: "3.0.0"),
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
let response = try await MyAPI().response(for: MyRequest(name: "My fancy name"))
print(response.results) // Our response is already a Swift type! More specifically, an instance of `MyRequest.Response`.
```

### Intercepting requests and responses

You can define request and response interceptors on your API for request mutation, mocking, and response post-processing.

- `requestInterceptors` run before Bifrost builds the final `URLRequest`
- `responseInterceptors` run after Bifrost has either decoded a network response or received a mocked response from a request interceptor
- both phases use `InterceptionResult<T>` with `.continue` and `.return(...)`
- mocked and real responses share the same `InterceptedResponse<Response>` wrapper, which exposes `body`, `httpResponse`, `statusCode`, and normalized `headerFields`
- response interceptors receive a `retry()` closure that reruns the original request pipeline
- unsuccessful HTTP statuses are surfaced after the response phase, so response interceptors can recover from responses like `401`

```swift
struct AddAuthorization: RequestInterceptor {
  let token: String

  func intercept<Request>(
    _ request: inout Request
  ) async throws -> InterceptionResult<InterceptedResponse<Request.Response>> where Request: Requestable {
    if var authenticated = request as? MyRequest {
      authenticated.token = token
      request = authenticated as! Request
    }

    return .continue
  }
}

struct RewriteResponse: ResponseInterceptor {
  func intercept<Response>(
    _ response: inout InterceptedResponse<Response>,
    retry: () async throws -> InterceptedResponse<Response>
  ) async throws -> InterceptionResult<InterceptedResponse<Response>> {
    return .continue
  }
}

struct MyAPI: API {
  let baseURL = URL(string: "https://api.myapi.com/v2/")!

  var requestInterceptors: [any RequestInterceptor] {
    [AddAuthorization(token: "<token>")]
  }

  var responseInterceptors: [any ResponseInterceptor] {
    [RewriteResponse()]
  }
}
```

Request interceptors mutate the request model itself, not `URLRequest`. That means any change they make still flows through the normal Bifrost request-building logic for path, query, headers, and body.

```swift
struct MockUser: RequestInterceptor {
  func intercept<Request>(
    _ request: inout Request
  ) async throws -> InterceptionResult<InterceptedResponse<Request.Response>> where Request: Requestable {
    guard request is GetUserRequest else {
      return .continue
    }

    let httpResponse = HTTPURLResponse(
      url: URL(string: "https://api.myapi.com/v2/user")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["X-Mocked": "true"]
    )!

    return .return(
      InterceptedResponse(
        body: GetUserRequest.Response(name: "Mocked User") as! Request.Response,
        httpResponse: httpResponse
      )
    )
  }
}
```

Response interceptors always receive the full intercepted response, including metadata, so they can make decisions based on the HTTP code or headers as well as the decoded body. They can also call `retry()` to rerun request interception, request building, and transport after doing recovery work like refreshing a token.

```swift
struct NormalizeUser: ResponseInterceptor {
  func intercept<Response>(
    _ response: inout InterceptedResponse<Response>,
    retry: () async throws -> InterceptedResponse<Response>
  ) async throws -> InterceptionResult<InterceptedResponse<Response>> where Response: Decodable {
    if response.statusCode == 202 {
      response.httpResponse = HTTPURLResponse(
        url: response.httpResponse.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: response.headerFields
      )!
    }

    return .continue
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
