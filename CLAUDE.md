# OpenPanel Swift SDK

Zero-dependency Swift SDK for OpenPanel analytics. Talks to `POST /track` on
`api.openpanel.dev`.

## Commands

```bash
swift build
swift test                      # Swift Testing (not XCTest); requires Swift 6 / Xcode 16
swift package clean
```

No `.xcodeproj` — SwiftPM only. CI builds on iOS / macOS / tvOS.

## Public API shape

`OpenPanel` is a shared singleton (`public static let shared`). `init` is
private; callers interact through the static facade:

```swift
OpenPanel.initialize(…)          // synchronous, fire-and-forget
OpenPanel.track("e", …)         // all other methods — also fire-and-forget
```

Public **methods** are synchronous and non-throwing. Calls spawn internal
`Task`s that hop onto the actor; network I/O, retries, and error handling
happen in the background. Errors are logged when `debug: true`. The two
public **read-only properties** `OpenPanel.deviceId` / `OpenPanel.sessionId`
are `async` (they read state from the actor).

Calling any method before `initialize` is a **fatal error** (`fatalError`).
This is intentional — the SDK must be initialized before use.

Instance methods on the actor are `async` (actor isolation) — the static
facade wraps them in `Task`. When adding a new public method, add both the
instance method and the static wrapper.

## Architecture

- `Sources/OpenPanel.swift` — public `actor OpenPanel`, the entry point (singleton + state only)
- `Sources/OpenPanel+Config.swift`, `OpenPanel+Error.swift` — public nested types
- `Sources/OpenPanel+API.swift` — public instance methods + the static fire-and-forget facade
- `Sources/OpenPanel+Helpers.swift` — internal `send`/`drainQueue`/`log`/`ensureInitialized` plus the test-only `initialize(_:session:)` and `resetForTesting()` overloads
- `Sources/OpenPanel+Transport.swift` — internal `Transport` struct (HTTP, retries, 401 silent-drop)
- `Sources/Models/` — payload types. **Public:** `OpenPanelEvent` (discriminated envelope), `TrackPayload`, `IdentifyPayload`, `GroupPayload`, `AssignGroupPayload`, `IncrementPayload`, `DecrementPayload`, `ProfileId`. **Internal:** `TrackResponse` (server response shape, not part of the public surface).

When adding a type, decide public vs. internal first. Public payloads go in `Sources/Models/`; internal helpers/transport types go next to their callsite (`Sources/OpenPanel+*.swift`). `TrackResponse` lives in `Models/` for historical reasons but is `internal` — keep new internal-only types alongside their consumer instead.

## Conventions

- Public nested types live in `OpenPanel+<Name>.swift` extensions, not inside `OpenPanel.swift`.
- Properties are plain `[String: String]` — no type-erasure wrappers.
- `swiftformat` is authoritative: 2-space indent, `--wraparguments before-first`, `--self init-only`. Run before committing.

## Gotchas

- **Tests share `MockURLProtocol.registry`.** Suites that use `MockURLProtocol` must be nested inside `MockBackedSuite` (which is `@Suite(.serialized)`). Pure-logic suites (e.g. `EncodingTests`) may live at the top level. A top-level `@Suite` that touches the registry will run in parallel and clobber it.
- **401 is a silent drop, no retry.** This is intentional — do not "fix" it by throwing.
- **`"Duplicate event"` plain-text body on 200 = success with no body.** Transport sniffs the prefix; don't tighten the decoder.
- **`identify` with only a `profileId` does not hit the network** — it just sets local state and attempts to drain the queue (no-op while `disabled` is `true`). Extras (`email`, `firstName`, `properties`, …) are required to trigger a request.
- **`revenue` is a `track` event** named `"revenue"` with reserved `__revenue` / `__deviceId` properties, not a separate endpoint.
- **Queued `track` events are stamped with `__timestamp`** so the server sees the original time, not the flush time. Other event types are not stamped. Preserve this when touching `send`/`flush`.
- **Queue is in-memory only** — lost on app restart. Don't add persistence without discussion.
- **`URLSession` is NOT part of `Config`.** Production code always uses `.shared`. Tests inject mock sessions via the internal `initialize(_:session:)` overload.
- **`setGroup`/`setGroups` require a `profileId`** — they accumulate groups locally but only send `assign_group` to the server when a profileId is set (via `identify`). Without one, the call logs a warning and skips the network request.
- **`clear()` does NOT reset global properties** — it only clears identity state (profileId, groups, deviceId, sessionId). Use `initialize` for a full reset.
- **`CancellationError` propagates immediately** in the transport retry loop — it is not retried.
- **Public API is fire-and-forget.** Static methods are synchronous, non-throwing. Errors are logged internally. Do not add `throws` to static facade methods.

## Testing

- Framework: Swift Testing (`import Testing`, `@Test`, `#expect`).
- Network is stubbed via `MockURLProtocol` + `URLSessionConfiguration.ephemeral` — tests never hit the real network.
- New suite → `extension MockBackedSuite { @Suite("Name") struct MyTests { … } }`.
- `MockURLProtocol.install { req in .success(.ok()) }` at the top of each test; `.reset()` is not needed because `install` resets captured state.
- Tests call instance methods (`await OpenPanel.shared.track(…)`) directly, NOT the static facade — static methods are fire-and-forget and return before the work completes.
- Singleton state persists across tests. Each test must call `OpenPanel.shared.initialize(…, session:)` (internal overload, injects mock session and resets state) before exercising the API. To assert pre-init behaviour, call `await OpenPanel.shared.resetForTesting()` — `internal`, reachable only via `@testable import OpenPanel`.
