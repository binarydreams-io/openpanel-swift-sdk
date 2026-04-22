# OpenPanel Swift SDK

Zero-dependency Swift SDK for OpenPanel analytics. Talks to `POST /track` on
`api.openpanel.dev`. Behavior mirrors the JS SDK — parity is intentional,
verify against `openapi.json` before changing wire format.

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
await OpenPanel.initialize(config: …)   // required, once
try await OpenPanel.track("e", …)       // all other methods
```

Every public method except `initialize` is `async throws` and throws
`OpenPanel.Error.notInitialized` when called before `initialize`. Network/HTTP
failures are still swallowed internally (only `.notInitialized` reaches the
caller). `initialize` resets all cached state (profile, groups, global props,
queue, device/session IDs) — a re-init is a hard reset.

Instance methods on the actor mirror the static ones; the static versions just
forward to `shared`. When adding a new public method, add both — keep the
shapes in sync.

## Architecture

- `Sources/OpenPanel/OpenPanel.swift` — public `actor OpenPanel`, the entry point
- `Sources/OpenPanel/OpenPanel+{Config,Error,SDK}.swift` — public nested types
- `Sources/OpenPanel/Models/` — **public** request payloads (`TrackPayload`, `IdentifyPayload`, `GroupPayload`, …) plus `AnyCodable` / `ProfileId`
- `Sources/OpenPanel/Internal/` — non-public: `Transport`, `TrackEnvelope`, `TrackResponse`

When adding a type, decide public vs. internal first — that decides which folder it goes in.

## Conventions

- Public nested types live in `OpenPanel+<Name>.swift` extensions, not inside `OpenPanel.swift`.
- `Properties` is `[String: AnyCodable]` — wrap values at the call site; do not accept `[String: Any]` in public API.
- `swiftformat` is authoritative: 2-space indent, `--wraparguments before-first`, `--self init-only`. Run before committing.

## Gotchas

- **Tests share `MockURLProtocol.registry`.** All test suites must be nested inside `MockBackedSuite` (which is `@Suite(.serialized)`). A top-level `@Suite` will run in parallel and clobber the handler registry.
- **401 is a silent drop, no retry.** This matches the JS SDK — do not "fix" it by throwing.
- **`"Duplicate event"` plain-text body on 200 = success with no body.** Transport sniffs the prefix; don't tighten the decoder.
- **`identify` with only a `profileId` does not hit the network** — it just sets local state and flushes the queue. Extras (`email`, `firstName`, `properties`, …) are required to trigger a request.
- **`revenue` is a `track` event** named `"revenue"` with reserved `__revenue` / `__deviceId` properties, not a separate endpoint.
- **Queued events are stamped with `__timestamp`** so the server sees the original time, not the flush time. Preserve this when touching `send`/`flush`.
- **Queue is in-memory only** — lost on app restart. Don't add persistence without discussion; the JS SDK behaves the same way.

## Testing

- Framework: Swift Testing (`import Testing`, `@Test`, `#expect`).
- Network is stubbed via `MockURLProtocol` + `URLSessionConfiguration.ephemeral` — tests never hit the real network.
- New suite → `extension MockBackedSuite { @Suite("Name") struct MyTests { … } }`.
- `MockURLProtocol.install { req in .success(.ok()) }` at the top of each test; `.reset()` is not needed because `install` resets captured state.
- Singleton state persists across tests. Each test must call `OpenPanel.initialize(…)` (which resets state) before exercising the API. To assert pre-init behaviour, call `await OpenPanel.shared.resetForTesting()` — `internal`, reachable only via `@testable import OpenPanel`.
