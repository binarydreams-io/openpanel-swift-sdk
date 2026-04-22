# OpenPanel SDK (Swift)

Zero-dependency Swift SDK for [OpenPanel](https://github.com/Openpanel-dev/openpanel) analytics.
Talks to the `POST /track` ingestion endpoint at `api.openpanel.dev`.

- iOS 16 / macOS 13 / tvOS 16 / watchOS 9 / visionOS 1
- No external dependencies (stdlib + Foundation + URLSession)
- Synchronous fire-and-forget API — no `await` or `try` at call sites
- `actor`-isolated singleton, all I/O on background tasks
- In-memory queue for `disabled: true` deferred startup

## Install

```swift
.package(url: "https://github.com/binarydreams-io/openpanel-swift-sdk.git", from: "1.0.0"),
```

## Usage

Call `OpenPanel.initialize(_:)` once at app start, then use the static API
from anywhere. All methods are synchronous — network I/O, retries, and error
handling happen in the background.

```swift
import OpenPanel

// App launch
OpenPanel.initialize(.init(
    clientId: "00000000-0000-0000-0000-000000000000",
    clientSecret: "your-client-secret",
    debug: true
))

// Anywhere in the app
OpenPanel.identify(.init(profileId: "user_123", email: "leo@example.com"))
OpenPanel.track("screen_view", properties: ["screen": "Home"])
OpenPanel.setGroup("acme-inc")       // requires identify() first
OpenPanel.increment(property: "login_count")  // requires identify() first
OpenPanel.revenue(999, properties: ["currency": "USD"])
```

Calling any method before `initialize` is a **fatal error** — the SDK must be
initialized before use. This is intentional: launch-time analytics
(`app_launch`, first-screen views, etc.) are critical, and a silent no-op
would let an "init order" bug ship to production. The crash surfaces the
misuse on the very first dev run so the developer can re-order startup.

`initialize` is idempotent — calling it a second time replaces the config and
wipes all cached state (profile, groups, global props, queue, device/session IDs).

## Configuration

```swift
OpenPanel.Config(
    clientId: String,                 // required — your project's client ID
    clientSecret: String,             // required — your project's client secret
    apiURL: URL,                      // default: https://api.openpanel.dev
    maxRetries: Int,                  // default: 3
    initialRetryDelay: Duration,      // default: 500ms (exponential backoff)
    debug: Bool,                      // default: false — print diagnostics to console
    maxQueueSize: Int,                // default: 1000 — FIFO eviction once exceeded
    filter: (OpenPanelEvent) -> Bool  // optional — drop events before they leave the process
)
```

`disabled` is **not** a `Config` field — it's a separate parameter on
`initialize(_:disabled:)`. See "Deferred startup" below.

## Deferred startup

Use `disabled: true` on `initialize` to queue events until you've bootstrapped:

```swift
OpenPanel.initialize(.init(clientId: "...", clientSecret: "..."), disabled: true)
OpenPanel.track("app_launch")   // queued in memory
// ...later
OpenPanel.ready()               // flushes the queue
```

## Filtering events

Pass a `filter` closure to drop events before they hit the network:

```swift
OpenPanel.initialize(.init(
    clientId: "...",
    clientSecret: "...",
    filter: { event in
        if case let .track(payload) = event, payload.name == "noisy_event" {
            return false
        }
        return true
    }
))
```

## Tests

Tests use Swift Testing (requires Xcode 16 / Swift 6) and `URLProtocol`-based mocking —
no network access required.

```bash
swift test
```
