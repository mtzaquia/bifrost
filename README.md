# ❄️ Bifrost

[![Tests](https://github.com/mtzaquia/bifrost/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/mtzaquia/bifrost/actions/workflows/tests.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://www.swift.org/)
[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue.svg)](https://github.com/mtzaquia/bifrost/blob/main/Package.swift)
![Class B](https://img.shields.io/badge/class-B-silver)

`Bifrost` is a typed JSON HTTP client for Swift, built around `Encodable`
request models and `Decodable` responses.

An API describes shared transport configuration. Each request describes its
path, method, inputs, and response type. Bifrost turns the two into a
`URLRequest`, runs an interception pipeline, and returns the decoded value.

- Derive query items or JSON bodies from request properties.
- Decode each endpoint into its own response type with `async`/`await`.
- Customize sessions, JSON coding, shared query items, and request headers.
- Mutate, mock, recover, or restart calls with ordered interceptors.
- Trace request lifecycles with privacy-conscious diagnostic levels.

```swift
let posts = try await PostsAPI().response(
  for: PostsForUser(userId: 1)
)
```

## Install

Bifrost supports iOS 17 and later and macOS 11 and later. It requires a Swift
6.2 toolchain and is distributed through Swift Package Manager.

Add the package dependency:

```swift
dependencies: [
  .package(url: "https://github.com/mtzaquia/bifrost.git", from: "3.0.5"),
]
```

Add the `Bifrost` product to the consuming target, then `import Bifrost` where
it is used. In Xcode, enter `https://github.com/mtzaquia/bifrost.git` in
**File → Add Package Dependencies**.

## Five-minute start

The following request loads posts for one user. Because `PostsForUser` uses the
default `GET` method, Bifrost encodes `userId` as a query item and requests
`https://jsonplaceholder.typicode.com/posts?userId=1`.

```swift
import Bifrost
import Foundation

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

struct PostsAPI: API {
  let baseURL = URL(
    string: "https://jsonplaceholder.typicode.com"
  )!
}

func loadPosts() async throws -> [Post] {
  try await PostsAPI().response(
    for: PostsForUser(userId: 1)
  )
}
```

That is the core idea: model an endpoint as a value, associate it with the
response it expects, and pass it to an API configuration.

## Documentation

- [Getting started](docs/getting-started.md) — configure an API, model an endpoint, and perform the first request.
- [Requests and responses](docs/requests-and-responses.md) — control paths, methods, parameters, headers, coding, transport, and failures.
- [Interceptors](docs/interceptors.md) — mutate requests, provide mock responses, transform raw responses, and restart recovery flows.
- [Diagnostics](docs/diagnostics.md) — inspect request lifecycles without exposing sensitive details by default.

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
