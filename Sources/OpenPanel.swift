import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

public actor OpenPanel {
  public static let shared = OpenPanel()

  private let api: API
  private var profileId: String?
  private var global: [String: String]?
  private var queue: [TrackHandlerPayload] = []
  private var options: Options?

  public struct Options: Sendable {
    public let clientId: String
    public var clientSecret: String?
    public var apiUrl: String?
    public var waitForProfile: Bool?
    public var filter: (@Sendable (TrackHandlerPayload) -> Bool)?
    public var disabled: Bool?

    public init(clientId: String, clientSecret: String? = nil, apiUrl: String? = nil, waitForProfile: Bool? = nil, filter: (@Sendable (TrackHandlerPayload) -> Bool)? = nil, disabled: Bool? = nil) {
      self.clientId = clientId
      self.clientSecret = clientSecret
      self.apiUrl = apiUrl
      self.waitForProfile = waitForProfile
      self.filter = filter
      self.disabled = disabled
    }
  }

  public static var sdkVersion: String {
    "0.1.0"
  }

  private init() {
    self.api = API(config: API.Config(baseUrl: "https://api.openpanel.dev"))
  }

  // MARK: - Public static API (sync wrappers)

  public static func initialize(options: Options) {
    Task { await shared._initialize(options) }
  }

  public static func ready() {
    Task { await shared._ready() }
  }

  public static func setGlobalProperties(_ properties: [String: String]) {
    Task { await shared._setGlobalProperties(properties) }
  }

  public static func track(name: String, properties: TrackProperties? = nil) {
    Task { await shared._track(name: name, properties: properties) }
  }

  public static func identify(payload: IdentifyPayload) {
    Task { await shared._identify(payload) }
  }

  public static func alias(payload: AliasPayload) {
    Task { await shared._send(.alias(payload)) }
  }

  public static func increment(payload: IncrementPayload) {
    Task { await shared._send(.increment(payload)) }
  }

  public static func decrement(payload: DecrementPayload) {
    Task { await shared._send(.decrement(payload)) }
  }

  public static func clear() {
    Task { await shared._clear() }
  }

  public static func flush() {
    Task { await shared.flush() }
  }

  public func flush() {
    let currentQueue = queue
    queue.removeAll()
    for item in currentQueue {
      _send(item)
    }
  }

  // MARK: - Actor-isolated implementations

  private func _initialize(_ options: Options) async {
    // Set options before any suspension point so concurrent events see them immediately
    self.options = options

    let userAgent = await DeviceInfo.getUserAgent()

    var defaultHeaders: [String: String] = [
      "openpanel-client-id": options.clientId,
      "openpanel-sdk-name": "swift",
      "openpanel-sdk-version": OpenPanel.sdkVersion,
      "user-agent": userAgent,
    ]

    if let clientSecret = options.clientSecret {
      defaultHeaders["openpanel-client-secret"] = clientSecret
    }

    await api.updateConfig(API.Config(
      baseUrl: options.apiUrl ?? "https://api.openpanel.dev",
      defaultHeaders: defaultHeaders
    ))

    let info = await DeviceInfo.getInfo()
    if global == nil { global = [:] }
    global?["__brand"] = info.brand
    global?["__device"] = info.device
    global?["__os"] = info.os
    global?["__osVersion"] = info.osVersion
    global?["__model"] = info.model
  }

  private func _ready() {
    options?.waitForProfile = false
    flush()
  }

  private func _setGlobalProperties(_ properties: [String: String]) {
    if var existing = global {
      for (key, value) in properties {
        existing[key] = value
      }
      global = existing
    } else {
      global = properties
    }
  }

  private func _track(name: String, properties: TrackProperties?) {
    var merged = global ?? [:]
    if let properties {
      merged.merge(properties) { _, new in new }
    }
    let payload = TrackPayload(
      name: name,
      properties: merged,
      profileId: properties?["profileId"] ?? profileId
    )
    _send(.track(payload))
  }

  private func _identify(_ payload: IdentifyPayload) {
    profileId = payload.profileId
    flush()

    if payload.firstName != nil || payload.lastName != nil || payload.email != nil || payload.avatar != nil || !(payload.properties?.isEmpty ?? true) {
      var updatedPayload = payload
      if let global {
        var mergedProperties = global
        if let payloadProperties = payload.properties {
          mergedProperties.merge(payloadProperties) { _, new in new }
        }
        updatedPayload.properties = mergedProperties
      }
      _send(.identify(updatedPayload))
    }
  }

  private func _clear() {
    profileId = nil
    global = nil
  }

  private func _send(_ payload: TrackHandlerPayload) {
    guard let options else {
      logError("OpenPanel not initialized. Call OpenPanel.initialize() first.")
      return
    }

    if options.disabled == true { return }

    if let filter = options.filter, !filter(payload) { return }

    if options.waitForProfile == true, profileId == nil {
      queue.append(payload)
      return
    }

    Task {
      let updatedPayload = self.ensureProfileId(payload)
      let result = await self.api.fetch(path: "/track", data: updatedPayload)
      if case let .failure(error) = result {
        self.logError("Error sending payload: \(error)")
      }
    }
  }

  private func ensureProfileId(_ payload: TrackHandlerPayload) -> TrackHandlerPayload {
    switch payload {
    case var .track(trackPayload):
      if trackPayload.profileId == nil {
        trackPayload.profileId = profileId
      }
      return .track(trackPayload)
    default:
      return payload
    }
  }

  private func logError(_ message: String) {
    print("OpenPanel Error: \(message)")
  }
}
