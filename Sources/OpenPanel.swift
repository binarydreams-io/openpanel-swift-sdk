//
//  OpenPanel.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation
import os

/// OpenPanel analytics client.
///
/// Usage is via the shared singleton: call `OpenPanel.initialize(_:)` once at
/// app start, then use the static fire-and-forget API (`OpenPanel.track`,
/// `OpenPanel.identify`, …). All methods are synchronous from the caller's
/// perspective — network I/O happens on background tasks. Errors are logged
/// internally when `debug: true`.
///
/// Behaviour:
/// - Events are sent immediately via `POST /track`.
/// - When `disabled` is `true`, events are queued in memory until ``ready()`` is called.
/// - The server returns `deviceId` and `sessionId`, which the client caches and reuses.
/// - Global properties are merged into every `track` event.
/// - A `filter` closure can drop events before they leave the process.
///
/// Queue is in-memory only: it does NOT persist across app restarts.
public actor OpenPanel {
  // MARK: - Singleton

  public static let shared = OpenPanel()

  // MARK: - State

  static let apiLog = Logger(subsystem: "dev.openpanel", category: "API")
  static let queueLog = Logger(subsystem: "dev.openpanel", category: "Queue")
  static let transportLog = Logger(subsystem: "dev.openpanel", category: "Transport")

  var config: Config?
  var transport: Transport?

  var profileId: ProfileId?
  var groups: Set<String> = []
  var global: [String: String] = [:]
  var queue: [OpenPanelEvent] = []
  /// When `true`, events are queued in memory until ``ready()`` is called.
  var disabled: Bool = false
  /// Set from `Config.waitForProfile`. While `true`, events queue locally
  /// until ``identify(_:)`` supplies a profileId. Independent of ``disabled``;
  /// both must be `false` for events to leave the process.
  var waitingForProfile: Bool = false
  /// `true` while ``drainQueue()`` is in flight. Concurrent ``send(_:)``
  /// calls route through the queue while this is set, so live events can't
  /// jump ahead of queued ones on the wire.
  var draining: Bool = false

  /// Server-issued device identifier. `nil` until the first successful response.
  public internal(set) var deviceId: String?
  /// Server-issued session identifier. `nil` until the first successful response;
  /// may be rotated by the server when the session expires.
  public internal(set) var sessionId: String?

  private init() {}
}
