# Interceptors

Interceptors add behavior around transport without changing each request model.
Request interceptors work with the final `URLRequest`; response interceptors
work with raw bytes and HTTP metadata before validation and decoding.

```text
Requestable → URLRequest → request interceptors → URLSession
            → response interceptors → status validation → decoding
```

## Mutate a request

Request interceptors run in `API.requestInterceptors` order after Bifrost has
applied the path, method, query, body, and request headers.

```swift
import Bifrost
import Foundation

struct AuthorizationInterceptor: RequestInterceptor {
  let token: String

  func intercept<Request>(
    _ context: inout InterceptionContext<Request>
  ) async throws -> InterceptionResult<InterceptedResponse>
  where Request: Requestable {
    context.urlRequest.setValue(
      "Bearer \(token)",
      forHTTPHeaderField: "Authorization"
    )

    return .continue
  }
}

struct AuthenticatedAPI: API {
  let baseURL = URL(string: "https://api.example.com/v1")!

  var requestInterceptors: [any RequestInterceptor] {
    [AuthorizationInterceptor(token: "<token>")]
  }
}
```

The generic context retains the original typed request. Check
`context.request` when an interceptor should apply only to selected request
types. Mutate `context.urlRequest`; it is the authoritative transport request
for that attempt.

## Return a response without transport

A request interceptor can provide an `InterceptedResponse` for a mock, cache,
or locally recovered result. This example matches the `GetPost` request from
[Requests and responses](requests-and-responses.md#choose-the-default-encoding):

```swift
struct MockPostInterceptor: RequestInterceptor {
  func intercept<Request>(
    _ context: inout InterceptionContext<Request>
  ) async throws -> InterceptionResult<InterceptedResponse>
  where Request: Requestable {
    guard context.request is GetPost else {
      return .continue
    }

    let response = HTTPURLResponse(
      url: context.urlRequest.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["X-Bifrost-Mock": "true"]
    )!

    return .return(
      InterceptedResponse(
        body: Data(#"{"id":1,"title":"Mocked","body":"Local"}"#.utf8),
        httpResponse: response
      )
    )
  }
}
```

Returning from the request phase skips the remaining request interceptors and
`URLSession`, but the supplied response still passes through every response
interceptor before validation and decoding.

## Transform a raw response

Response interceptors run in `API.responseInterceptors` order. They can replace
the raw body, replace `httpResponse`, or return another
`InterceptedResponse`.

```swift
struct NormalizeAcceptedStatus: ResponseInterceptor {
  func intercept(
    _ response: inout InterceptedResponse
  ) async throws -> InterceptionResult<InterceptedResponse> {
    guard response.statusCode == 202 else {
      return .continue
    }

    response.httpResponse = HTTPURLResponse(
      url: response.httpResponse.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: response.headerFields
    )!

    return .continue
  }
}
```

Because status validation comes later, this phase can inspect and recover from
a `401`, or turn an otherwise accepted response into an error. Transport errors
do not enter the response phase.

## Control the pipeline

Both interceptor protocols return `InterceptionResult`:

- `.continue` keeps in-place mutations and advances to the next interceptor or
  pipeline stage.
- `.return(response)` stops the current phase. A request interceptor skips
  transport; a response interceptor skips the remaining response interceptors.
  Status validation and decoding still run.
- `.restart` stops the current phase and rebuilds the request from the original
  request value.

A request-phase restart discards mutations to its `URLRequest` and starts the
request interceptor chain again without transporting that attempt. A
response-phase restart starts the full pipeline again, including transport.
External side effects such as storing a refreshed credential remain in effect.

Bifrost does not impose a restart limit. Recovery logic must eventually
continue or throw to avoid an infinite pipeline. Errors thrown by any
interceptor stop the request and propagate to the caller.

If an interceptor shares mutable state across concurrent calls, that state is
responsible for its own synchronization.

Next: [Requests and responses](requests-and-responses.md) · [Diagnostics](diagnostics.md)
