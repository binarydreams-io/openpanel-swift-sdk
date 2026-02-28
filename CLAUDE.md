# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenPanel Swift SDK — an analytics SDK for Apple platforms (iOS 13+, macOS 10.15+, tvOS 15+). Licensed under AGPL-3.0.

## Build Commands

```bash
# Build for all platforms
swift build

# Build for a specific platform (useful since UIKit/AppKit code is conditionally compiled)
xcodebuild -scheme OpenPanel -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild -scheme OpenPanel -destination 'platform=macOS'
xcodebuild -scheme OpenPanel -destination 'platform=tvOS Simulator,name=Apple TV'
```

There are no tests or linting configured in this project.

## Architecture

Single-target Swift Package (`OpenPanel`) with no external dependencies.

### Source Layout

- `Sources/OpenPanel.swift` — Main SDK class. Singleton (`OpenPanel.shared`) with static convenience methods. All public API lives here: `initialize`, `track`, `identify`, `alias`, `increment`, `decrement`, `setGlobalProperties`, `clear`, `flush`, `ready`.
- `Sources/Internal/API.swift` — HTTP client with async/await, exponential backoff retry (default 3 retries, 0.5s initial delay). Posts JSON to the OpenPanel API.
- `Sources/Internal/DeviceInfo.swift` — Platform-specific device metadata collection using conditional compilation (`#if canImport(UIKit)`, `#if os(macOS)`, etc.).
- `Sources/Models/Payloads.swift` — Request payload types and the `TrackHandlerPayload` enum that wraps all event types for encoding.
- `Sources/Models/AnyCodable.swift` — Type-erased `Codable` wrapper enabling `[String: Any]` properties in the public API.

### Key Patterns

- **Thread safety**: `@unchecked Sendable` conformance. Global properties protected by a concurrent `DispatchQueue` with barrier writes. API calls serialized via an `OperationQueue` (max 1 concurrent).
- **Event queuing**: When `waitForProfile` is enabled, events queue until `identify()` or `ready()` is called, then flush.
- **Property merging**: Device info → global properties → per-event properties (later overrides earlier).
- **Conditional compilation**: Platform-specific blocks for iOS/tvOS (UIKit), macOS (AppKit), and tvOS-specific uname() calls. Be careful editing `DeviceInfo.swift` — each platform path must compile independently.

### Swift Version

Package uses swift-tools-version 6.2 with strict concurrency. The main class is `final class OpenPanel: @unchecked Sendable`.
