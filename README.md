# OpenPanel SDK (Swift)

[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-blue.svg)](#requirements)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Zero-dependency Swift SDK for [OpenPanel](https://openpanel.dev) — an
open-source, privacy-friendly alternative to Mixpanel and GA. Sends events to
`POST /track` at `api.openpanel.dev` (or your self-hosted instance).

- iOS 16 / macOS 13 / tvOS 16 / watchOS 9 / visionOS 1
- Zero dependencies (stdlib + Foundation + URLSession only)
- Synchronous fire-and-forget API — no `await` or `try` at call sites
- `actor`-isolated singleton, all I/O on background tasks
- In-memory queue for `disabled: true` deferred startup, `waitForProfile`, and post-`identify` drain
- Order-preserving drain: live events submitted while the queue is draining stay behind queued events on the wire
- Per-event device metadata (`__brand`, `__osVersion`, `__model`, `__version`, `__buildNumber`, `__screen*`, `__wifi`)
- Built on Swift Concurrency — Sendable, strict-concurrency-clean

## Install

Swift Package Manager (SPM-only — no CocoaPods or Carthage):

```swift
.package(url: "https://github.com/binarydreams-io/openpanel-swift-sdk.git", from: "1.0.0"),
```

Or in Xcode: **File → Add Package Dependencies…** and paste the URL.

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
OpenPanel.alias(profileId: "user_123", alias: "anon_42")  // merge anon → logged-in profile
```

Calling any method before `initialize` is a **fatal error** — the SDK must be
initialized before use. This is intentional: launch-time analytics
(`app_launch`, first-screen views, etc.) are critical, and a silent no-op
would let an "init order" bug ship to production. The crash surfaces the
misuse on the very first dev run so the developer can re-order startup.

`initialize` is idempotent — calling it a second time replaces the config and
wipes all cached state (profile, groups, global props, queue, device/session IDs).

### Async API

The static facade returns immediately and discards errors. If you need to
`await` the actor directly (for example, to read `deviceId`/`sessionId`, or
to deterministically order calls in tests), go through `OpenPanel.shared`:

```swift
await OpenPanel.shared.track("screen_view")
let deviceId = await OpenPanel.deviceId
let sessionId = await OpenPanel.sessionId
```

> **Ordering caveat.** Two back-to-back static calls
> (`OpenPanel.track("a"); OpenPanel.track("b")`) each spawn an unstructured
> `Task` and are not guaranteed to reach the actor in submission order. If
> ordering matters, use the instance API and `await` each call.

## Public API

| Method | Purpose |
| --- | --- |
| `initialize(_:disabled:)` | Configure the singleton. Required before any other call. |
| `ready()` | Unblock queued events (pair with `disabled: true`). |
| `clear()` | Reset identity (profile, groups, device, session). Re-arms `waitForProfile`. |
| `track(_:properties:profileId:groups:)` | Send a track event. |
| `identify(_:)` | Set the active profile and update profile attributes. |
| `alias(profileId:alias:)` | Merge an anonymous profile into a logged-in one. |
| `setGlobalProperties(_:)` | Merge into the global property map applied to every track event. |
| `setGroup(_:)` / `setGroups(_:)` | Attach the current profile to one or more groups. Requires `identify`. |
| `upsertGroup(_:)` | Create or update a group record. |
| `increment(property:value:profileId:)` / `decrement(...)` | Adjust a numeric profile property. Requires `identify`. |
| `revenue(_:properties:deviceId:)` | Send a `revenue` track event with a reserved `__revenue` property. |
| `flush()` | Drain the in-memory queue. No-op while gated. |
| `deviceId` / `sessionId` | `async` reads of the server-issued IDs. |

## Configuration

```swift
OpenPanel.Config(
    clientId: String,                 // required — your project's client ID
    clientSecret: String,             // required — your project's client secret
    apiURL: URL,                      // default: https://api.openpanel.dev
    maxRetries: Int,                  // default: 3
    initialRetryDelay: Duration,      // default: 500ms (exponential backoff)
    maxQueueSize: Int,                // default: 1000 — FIFO eviction once exceeded
    waitForProfile: Bool,             // default: false — queue events until identify() supplies a profileId
    filter: (OpenPanelEvent) -> Bool, // optional — drop events before they leave the process
    debug: Bool                       // default: false — print diagnostics to console
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

`waitForProfile: true` is a separate gate that queues events until
`identify(_:)` supplies a `profileId`. Both gates must be cleared for events
to leave the process. `clear()` re-arms `waitForProfile` on logout, returning
the SDK to its pre-login queueing state.

The queue is in-memory only — it does not persist across app restarts. When
the cap (`maxQueueSize`, default `1000`) is reached, the oldest event is
dropped (FIFO).

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

## Reserved properties

The SDK manages its own set of `__`-prefixed property keys and stamps them on
every `track` event:

| Key | Source | Notes |
| --- | --- | --- |
| `__brand` | constant `"Apple"` | |
| `__osVersion` | `UIDevice` / `WKInterfaceDevice` / `ProcessInfo` | platform-dependent |
| `__model` | `sysctlbyname("hw.machine"\|"hw.model")` | Simulator returns `SIMULATOR_MODEL_IDENTIFIER` |
| `__version` | `CFBundleShortVersionString` | omitted if absent |
| `__buildNumber` | `CFBundleVersion` | omitted if absent |
| `__screenWidth` / `__screenHeight` / `__screenDpi` | `UIScreen` / `NSScreen` / `WKInterfaceDevice` | best-effort |
| `__wifi` | `NWPathMonitor` snapshot | omitted until first path update |
| `__timestamp` | `Date.now` (ISO 8601) | stamped on **queued** track events so the server records the original time, not the flush time |
| `__revenue` / `__deviceId` | `revenue(_:properties:deviceId:)` | reserved for revenue events |

Caller-supplied `__`-prefixed keys are **stripped** from `track`, `revenue`,
`identify`, and `setGlobalProperties`. User input cannot override SDK-managed
semantics.

## Login → logout flow

```swift
// On login: tell OpenPanel who the user is. Drains anything that was
// queued while waitForProfile was set.
OpenPanel.identify(.init(profileId: "user_123", email: "leo@example.com"))
OpenPanel.setGlobalProperties(["plan": "pro"])

// On logout: clear identity. waitForProfile is re-armed if it was set
// in Config — events tracked between logout and the next identify()
// are queued, not dropped.
OpenPanel.clear()
```

`clear()` does **not** clear global properties. Use a fresh `initialize` for
a full reset.

## Requirements

- Xcode 16+ / Swift 6.3 (the package targets `swift-tools-version: 6.3`)
- iOS 16 / macOS 13 / tvOS 16 / watchOS 9 / visionOS 1

## Tests

Tests use [Swift Testing](https://developer.apple.com/xcode/swift-testing/)
and `URLProtocol`-based mocking — no network access required.

```bash
swift test
```

CI runs the suite on iOS, macOS, and tvOS.

## Contributing

Issues and pull requests welcome. Before opening a PR:

- Run `swift test` and make sure the suite is green.
- Run `swiftformat .` — `.swiftformat` is authoritative.
- For new public surface, add both an instance method on the actor and a
  static wrapper on the facade.

## License

MIT — see [LICENSE](LICENSE).
