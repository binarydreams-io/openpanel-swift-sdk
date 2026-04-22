//
//  OpenPanel+Helpers.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation
import os

extension OpenPanel {
  /// Internal overload that injects a custom `URLSession` (for testing with `MockURLProtocol`).
  func initialize(_ config: Config, session: URLSession, disabled: Bool = false) {
    self.config = config
    transport = Transport(config: config, session: session)
    profileId = nil
    groups.removeAll()
    global.removeAll()
    queue.removeAll()
    deviceId = nil
    sessionId = nil
    self.disabled = disabled
  }

  /// Fully un-configures the singleton. Only for tests — `@testable import OpenPanel`
  /// is required to reach it. Not part of the public API.
  func resetForTesting() {
    config = nil
    transport = nil
    profileId = nil
    groups.removeAll()
    global.removeAll()
    queue.removeAll()
    deviceId = nil
    sessionId = nil
    disabled = false
  }

  /// Crashes if the SDK has not been configured.
  ///
  /// Calling any public method before `initialize` is an intentional **fatal error**:
  /// analytics from the very first launch (`app_launch`, etc.) are critical, and a silent
  /// no-op would let the bug ship to production. The crash surfaces the misuse on the first
  /// dev run so the developer can re-order initialization before any other code path.
  func ensureInitialized() {
    guard config != nil, transport != nil else {
      fatalError("[OpenPanel] SDK not initialized. Call OpenPanel.initialize(_:) first.")
    }
  }

  func log(_ message: @autoclosure () -> String, to logger: Logger = OpenPanel.apiLog) {
    guard config?.debug == true else { return }
    let text = message()
    logger.debug("\(text)")
  }

  @discardableResult
  func send(_ envelope: OpenPanelEvent) async -> Bool {
    guard let config, let transport else { return false }

    if let filter = config.filter, !filter(envelope) {
      log("Filtered event: \(envelope)")
      return true
    }

    if disabled {
      queue.append(stamped(envelope))
      if queue.count > config.maxQueueSize {
        let dropped = queue.removeFirst()
        log("Queue full (max=\(config.maxQueueSize)) — dropped oldest: \(dropped)", to: OpenPanel.queueLog)
      }
      log("Queued event: \(envelope)", to: OpenPanel.queueLog)
      return true
    }

    log("Sending event: \(envelope)", to: OpenPanel.transportLog)
    do {
      let response: TrackResponse? = try await transport.post(path: "/track", body: envelope)
      if let response {
        deviceId = response.deviceId
        sessionId = response.sessionId
      }
      return true
    } catch {
      log("Send failed: \(error)", to: OpenPanel.transportLog)
      return false
    }
  }

  /// Stamps queued `track` events with `__timestamp` so the server records
  /// the original event time rather than the flush time.
  private func stamped(_ envelope: OpenPanelEvent) -> OpenPanelEvent {
    guard case var .track(payload) = envelope else { return envelope }
    var props = payload.properties ?? [:]
    if props["__timestamp"] == nil {
      props["__timestamp"] = Date.now.ISO8601Format(.iso8601WithTimeZone(includingFractionalSeconds: true))
    }
    payload.properties = props
    return .track(payload)
  }

  /// Backfills `profileId` on `track` events that were queued before `identify`.
  /// Other event types either carry an explicit profileId or don't need one.
  private func enriched(_ envelope: OpenPanelEvent) -> OpenPanelEvent {
    guard case var .track(payload) = envelope, payload.profileId == nil, let profileId else {
      return envelope
    }
    payload.profileId = profileId
    return .track(payload)
  }

  func drainQueue() async {
    guard config != nil, !disabled else { return }
    let pending = queue
    queue.removeAll()
    for (index, envelope) in pending.enumerated() {
      if await !send(enriched(envelope)) {
        // Network failure during drain — preserve order by re-queueing the
        // failed event together with anything we haven't tried yet.
        queue.insert(contentsOf: pending[index...], at: 0)
        return
      }
    }
  }
}
