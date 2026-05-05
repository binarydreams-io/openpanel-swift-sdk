//
//  OpenPanel+Config.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

public extension OpenPanel {
  /// Configuration for the OpenPanel SDK. Pass to ``OpenPanel/initialize(_:)``.
  struct Config: Sendable {
    /// Project client ID issued by the OpenPanel dashboard. Required.
    public var clientId: String
    /// Project client secret. Required for revenue tracking and identified events.
    public var clientSecret: String
    /// Ingestion endpoint. Defaults to `https://api.openpanel.dev`.
    public var apiURL: URL
    /// Number of additional attempts after a transient failure before giving up. `0` disables retries.
    public var maxRetries: Int
    /// Backoff delay for the first retry; each subsequent retry doubles the delay (exponential).
    public var initialRetryDelay: Duration
    /// Maximum number of events kept in the in-memory queue while the SDK is paused.
    /// When the cap is reached, the oldest event is dropped (FIFO eviction).
    public var maxQueueSize: Int
    /// When `true`, all events are queued in memory until ``OpenPanel/identify(_:)``
    /// supplies a `profileId`, at which point the queue is drained automatically.
    /// Independent of the `disabled` flag — both must be cleared for events to send.
    public var waitForProfile: Bool
    /// Optional filter: return `false` to drop an event before it leaves the process.
    public var filter: (@Sendable (OpenPanelEvent) -> Bool)?
    /// When `true`, the SDK prints diagnostics through `OSLog`.
    public var debug: Bool

    var sdkName: String {
      "swift"
    }

    var sdkVersion: String {
      "1.0.0"
    }

    public init(
      clientId: String,
      clientSecret: String,
      apiURL: URL = URL(string: "https://api.openpanel.dev")!,
      maxRetries: Int = 3,
      initialRetryDelay: Duration = .milliseconds(500),
      maxQueueSize: Int = 1000,
      waitForProfile: Bool = false,
      filter: (@Sendable (OpenPanelEvent) -> Bool)? = nil,
      debug: Bool = false
    ) {
      self.clientId = clientId
      self.clientSecret = clientSecret
      self.apiURL = apiURL
      self.maxRetries = maxRetries
      self.initialRetryDelay = initialRetryDelay
      self.maxQueueSize = maxQueueSize
      self.waitForProfile = waitForProfile
      self.filter = filter
      self.debug = debug
    }
  }
}
