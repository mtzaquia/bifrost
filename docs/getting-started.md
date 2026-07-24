# Getting started

Bifrost has two primary parts: an `API` value that holds shared configuration
and a `Requestable` value that describes one endpoint and its response type.

## Configure an API

An API needs a base URL. The default configuration uses `URLSession.shared`,
standard JSON coding, no shared query items, and no interceptors.

```swift
import Bifrost
import Foundation

struct PostsAPI: API {
  let baseURL = URL(
    string: "https://jsonplaceholder.typicode.com"
  )!
}
```

Keep the API value for as long as its custom session or interceptor state needs
to live. Bifrost does not invalidate a session supplied through `urlSession`.

## Model an endpoint

A request is `Encodable` and associates itself with one `Decodable` response
type. This request uses the default `GET` method, so its `userId` property
becomes a query item.

```swift
struct Post: Decodable, Sendable {
  let id: Int
  let title: String
  let body: String
}

struct PostsForUser: Requestable, Sendable {
  let userId: Int

  var path: String { "posts" }

  typealias Response = [Post]
}
```

Bifrost appends `path` to the API's base URL. Here, the resulting request is
`GET https://jsonplaceholder.typicode.com/posts?userId=1`.

## Perform the request

Call `response(for:)` from an asynchronous context. The return type follows
from the request, so no type annotation or separate decoding step is needed.

```swift
func loadPosts() async throws -> [Post] {
  try await PostsAPI().response(
    for: PostsForUser(userId: 1)
  )
}
```

Each call builds a new `URLRequest` and runs independently. Encoding,
interceptor, transport, status, and decoding failures are thrown to the caller.

Next: [Requests and responses](requests-and-responses.md) · [Interceptors](interceptors.md)
