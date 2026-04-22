# OpenPanel SDK (Swift)

Zero-dependency Swift SDK for [OpenPanel](https://github.com/Openpanel-dev/openpanel) analytics.
Talks to the `POST /track` ingestion endpoint described in `openapi.json`.

- iOS 17 / macOS 14 / tvOS 17 / watchOS 10 / visionOS 1
- No external dependencies (stdlib + Foundation + URLSession)
- `async`/`await` API, `actor`-isolated singleton
- In-memory queue (lost on app restart) for `disabled: true` startup

## Install

```swift
.package(url: "https://github.com/<you>/OpenPanel.git", from: "0.1.0"),
```

## Usage

The SDK is a shared singleton. Call `OpenPanel.initialize(config:)` once at app
start, then use the static API from anywhere. Calling any other method before
`initialize` throws `OpenPanel.Error.notInitialized`.

```swift
import OpenPanel

// App launch
await OpenPanel.initialize(config: .init(
    clientId: "00000000-0000-0000-0000-000000000000",
    clientSecret: "optional-for-server-side-use",
    apiURL: URL(string: "https://api.openpanel.dev")!,
    debug: true
))

// Anywhere in the app
try await OpenPanel.identify(.init(profileId: "user_123", email: "leo@example.com"))
try await OpenPanel.track("screen_view", properties: ["screen": AnyCodable("Home")])
try await OpenPanel.setGroup("acme-inc")
try await OpenPanel.increment(property: "login_count")
try await OpenPanel.revenue(999, properties: ["currency": AnyCodable("USD")])
```

`initialize` is idempotent — calling it a second time replaces the config and
wipes all cached state (profile, groups, global props, queue, device/session IDs).

## Deferred startup

Use `disabled: true` if you want to queue events until you've bootstrapped
(e.g. after loading a user profile from disk):

```swift
await OpenPanel.initialize(config: .init(clientId: "...", disabled: true))
try await OpenPanel.track("app_launch")   // queued
// ...later
try await OpenPanel.ready()               // flushes the queue
```

## Error handling

Every call except `initialize` is `throws`. The only thrown error is
`OpenPanel.Error.notInitialized` — network, HTTP and decoding failures are
swallowed internally (the SDK logs them when `debug: true`). Wrap calls in
`try?` if you want fully fire-and-forget semantics:

```swift
try? await OpenPanel.track("screen_view")
```

## Endpoints covered

| Method | Path              | Covered |
|--------|-------------------|---------|
| POST   | `/track`          | ✅      |
| GET    | `/track/device-id`| (add if needed) |

`replay` and `alias` envelope types are intentionally omitted (same scope as `openapi.json`).

## Tests

Tests use Swift Testing (requires Xcode 16 / Swift 6) and `URLProtocol`-based mocking —
no network access required.

```bash
swift test
```
