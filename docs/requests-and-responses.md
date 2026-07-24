# Requests and responses

`Requestable` controls endpoint-specific URL, method, parameters, body, headers,
and response type. `API` supplies the configuration shared by those endpoints.

## Build the URL

Bifrost appends a nonempty `Requestable.path` to `API.baseURL`. An empty path
uses the base URL unchanged.

Query items are appended in this order:

1. Items already present in `baseURL`.
2. Items returned by `API.queryParameters()`.
3. Items returned by `Requestable.queryParameters()`.

Duplicate names are preserved. This allows an API to supply shared values while
a request adds another value with the same name.

```swift
struct SearchAPI: API {
  let baseURL = URL(string: "https://api.example.com/v1?client=ios")!

  func queryParameters() -> [URLQueryItem] {
    [URLQueryItem(name: "locale", value: "en")]
  }
}
```

## Choose the default encoding

The request method determines how the synthesized `Encodable` representation is
used:

| Method | Default query | Default body |
| --- | --- | --- |
| `GET` | Encoded properties | None |
| `POST` | None | JSON |
| `PUT` | None | JSON |
| `PATCH` | None | JSON |
| `DELETE` | None | None |

Default `GET` encoding requires a keyed JSON object. Scalar properties become
query items, array properties become repeated items with the same name, and
properties encoded as `nil` are omitted.

A property used in `path` is still part of the default query encoding. Override
`queryParameters()` when that property should appear only in the path:

```swift
struct GetPost: Requestable {
  let id: Int

  var path: String { "posts/\(id)" }

  func queryParameters() throws -> [URLQueryItem] {
    []
  }

  typealias Response = Post
}
```

Override `queryParameters()` whenever the server's URL representation should
not follow the encoded request properties. `API.jsonEncoder` does not affect
this default `GET` conversion.

## Send a JSON body and headers

`POST`, `PUT`, and `PATCH` encode the entire request with `API.jsonEncoder`.
Bifrost does not add a `Content-Type` header automatically.

```swift
struct CreatePost: Requestable {
  let title: String
  let body: String
  let userId: Int

  var path: String { "posts" }
  var method: HTTPMethod { .post }
  var headerFields: [String: String] {
    ["Content-Type": "application/json"]
  }

  typealias Response = Post
}
```

Headers are applied before request interception. A request interceptor can add
API-wide headers or replace a request-specific value.

Override `bodyParameters(_:)` to produce another body representation or to send
a body with a method whose default is `nil`.

## Configure transport and JSON coding

An API can supply a custom session and JSON strategies:

```swift
struct ServiceAPI: API {
  let baseURL = URL(string: "https://api.example.com/v1")!
  let urlSession: URLSession

  var jsonEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }

  var jsonDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
```

The encoder is passed to `bodyParameters(_:)`. The decoder runs only after
response interception and status validation.

## Ignore an accepted response body

Use `EmptyResponse` when the response body should not be decoded:

```swift
struct DeletePost: Requestable {
  let id: Int

  var path: String { "posts/\(id)" }
  var method: HTTPMethod { .delete }

  typealias Response = EmptyResponse
}
```

Response interceptors and status validation still run. Only decoding is
skipped.

## Handle failures

Response interceptors run before status validation. Final status codes from
`200` through `399` proceed to decoding; every other code throws
`BifrostError.unsuccessfulStatusCode` with the exact status.

Request encoding errors, interceptor errors, transport errors, cancellation,
and decoding errors propagate to the caller. A non-HTTP transport response
throws `URLError.badServerResponse`. A transport failure has no raw response,
so response interceptors do not run for it.

Next: [Interceptors](interceptors.md) · [Diagnostics](diagnostics.md)
