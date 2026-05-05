//
//  OpenPanel+API.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

// MARK: - Public instance API

public extension OpenPanel {
  /// Configure the singleton. Must be called before any other public API.
  /// Calling a second time replaces the config/transport and resets all cached state.
  /// Pass `disabled: true` to queue events until ``ready()`` is called.
  func initialize(_ config: Config, disabled: Bool = false) {
    self.config = config
    transport = Transport(config: config)
    profileId = nil
    groups.removeAll()
    global.removeAll()
    queue.removeAll()
    deviceId = nil
    sessionId = nil
    self.disabled = disabled
    waitingForProfile = config.waitForProfile
    draining = false
  }

  /// Unblock queued events. Pair with `initialize(_:, disabled: true)` for deferred startup.
  func ready() async {
    ensureInitialized()
    disabled = false
    await drainQueue()
  }

  /// Reset cached identity (profile, groups, device, session).
  func clear() {
    ensureInitialized()
    profileId = nil
    groups.removeAll()
    deviceId = nil
    sessionId = nil
    if config?.waitForProfile == true {
      waitingForProfile = true
    }
  }

  func setGlobalProperties(_ properties: [String: String]) {
    ensureInitialized()
    global.merge(stripReserved(properties)) { _, new in new }
  }

  func track(
    _ name: String,
    properties: [String: String]? = nil,
    profileId: ProfileId? = nil,
    groups: [String]? = nil
  ) async {
    ensureInitialized()
    let payload = buildTrackPayload(
      name: name,
      userProperties: properties,
      reserved: [:],
      profileId: profileId ?? self.profileId,
      extraGroups: groups
    )
    await send(.track(payload))
  }

  /// Merge `alias` (often the anonymous profile id assigned before login) into
  /// `profileId` (the canonical, post-login id) server-side.
  func alias(profileId: String, alias: String) async {
    ensureInitialized()
    await send(.alias(AliasPayload(profileId: profileId, alias: alias)))
  }

  func identify(_ payload: IdentifyPayload) async {
    ensureInitialized()

    profileId = payload.profileId
    waitingForProfile = false

    // Attempt to flush queued events. No-op while `disabled` is still `true`.
    await drainQueue()

    // Only hit the API if caller supplied more than just the ID.
    let hasExtras = payload.firstName != nil || payload.lastName != nil
      || payload.email != nil || payload.avatar != nil
      || (payload.properties?.isEmpty == false)

    guard hasExtras else { return }

    var enrichedPayload = payload
    if let userProperties = payload.properties {
      var mergedProperties = global
      mergedProperties.merge(stripReserved(userProperties)) { _, new in new }
      enrichedPayload.properties = mergedProperties
    } else if !global.isEmpty {
      enrichedPayload.properties = global
    }

    await send(.identify(enrichedPayload))
  }

  func upsertGroup(_ payload: GroupPayload) async {
    ensureInitialized()
    await send(.group(payload))
  }

  func setGroup(_ groupId: String) async {
    ensureInitialized()
    guard !groups.contains(groupId) else { return }
    groups.insert(groupId)
    guard let profileId else {
      log("Ignored setGroup('\(groupId)') — no profileId set")
      return
    }
    await send(.assignGroup(AssignGroupPayload(groupIds: [groupId], profileId: profileId)))
  }

  func setGroups(_ groupIds: [String]) async {
    ensureInitialized()
    let newGroups = groupIds.filter { !groups.contains($0) }
    guard !newGroups.isEmpty else { return }
    groups.formUnion(newGroups)
    guard let profileId else {
      log("Ignored setGroups(\(newGroups)) — no profileId set")
      return
    }
    await send(.assignGroup(AssignGroupPayload(groupIds: newGroups, profileId: profileId)))
  }

  func increment(property: String, value: Double? = nil, profileId: ProfileId? = nil) async {
    ensureInitialized()
    guard let resolvedProfileId = profileId ?? self.profileId else {
      log("Ignored increment('\(property)') — no profileId set")
      return
    }
    await send(.increment(IncrementPayload(profileId: resolvedProfileId, property: property, value: value)))
  }

  func decrement(property: String, value: Double? = nil, profileId: ProfileId? = nil) async {
    ensureInitialized()
    guard let resolvedProfileId = profileId ?? self.profileId else {
      log("Ignored decrement('\(property)') — no profileId set")
      return
    }
    await send(.decrement(DecrementPayload(profileId: resolvedProfileId, property: property, value: value)))
  }

  /// Revenue is a regular `track` event named `"revenue"` with a reserved `__revenue` property.
  /// The server requires a client secret for revenue unless the project allows unsafe revenue.
  func revenue(_ amount: Double, properties: [String: String]? = nil, deviceId: String? = nil) async {
    ensureInitialized()
    var reservedProperties = ["__revenue": String(amount)]
    if let deviceId { reservedProperties["__deviceId"] = deviceId }
    let payload = buildTrackPayload(
      name: "revenue",
      userProperties: properties,
      reserved: reservedProperties,
      profileId: profileId,
      extraGroups: nil
    )
    await send(.track(payload))
  }

  func flush() async {
    ensureInitialized()
    await drainQueue()
  }
}

// MARK: - Static facade (fire-and-forget)

/// Synchronous, non-throwing entry points for callers that don't want to
/// `await`. Each method spawns an unstructured `Task` that hops onto the
/// actor, then returns immediately. Errors are caught and logged inside
/// the actor — they never surface here.
///
/// Ordering caveat: the Swift runtime does not guarantee that two
/// back-to-back `Task {}` invocations will reach the actor in submission
/// order, so `OpenPanel.track("a"); OpenPanel.track("b")` may arrive at
/// the server in either order. Tests and code paths that need a specific
/// ordering must use the instance API (`await OpenPanel.shared.track(…)`)
/// instead.
public extension OpenPanel {
  /// Configure the singleton. Returns immediately; the actor work runs
  /// asynchronously.
  static func initialize(_ config: Config, disabled: Bool = false) {
    Task(name: "OpenPanel.initialize") { await shared.initialize(config, disabled: disabled) }
  }

  /// Unblock queued events. See instance ``ready()``.
  static func ready() {
    Task(name: "OpenPanel.ready") { await shared.ready() }
  }

  /// Reset cached identity (profile, groups, device, session).
  /// Does NOT clear global properties. See instance ``clear()``.
  static func clear() {
    Task(name: "OpenPanel.clear") { await shared.clear() }
  }

  /// Merge into the global property map. Reserved (`__`-prefixed) keys
  /// are stripped. See instance ``setGlobalProperties(_:)``.
  static func setGlobalProperties(_ properties: [String: String]) {
    Task(name: "OpenPanel.setGlobalProperties") { await shared.setGlobalProperties(properties) }
  }

  /// Send a track event. Stamped with device metadata, merged with global
  /// properties, then sent or queued. See instance ``track(_:properties:profileId:groups:)``.
  static func track(
    _ name: String,
    properties: [String: String]? = nil,
    profileId: ProfileId? = nil,
    groups: [String]? = nil
  ) {
    Task(name: "OpenPanel.track") {
      await shared.track(name, properties: properties, profileId: profileId, groups: groups)
    }
  }

  /// Set the active profile and optionally update profile attributes.
  /// See instance ``identify(_:)``.
  static func identify(_ payload: IdentifyPayload) {
    Task(name: "OpenPanel.identify") { await shared.identify(payload) }
  }

  /// Create or update a group record. See instance ``upsertGroup(_:)``.
  static func upsertGroup(_ payload: GroupPayload) {
    Task(name: "OpenPanel.upsertGroup") { await shared.upsertGroup(payload) }
  }

  /// Attach the current profile to a group. Requires a `profileId` to have
  /// been set via ``identify(_:)``; otherwise it logs and skips the network
  /// request. See instance ``setGroup(_:)``.
  static func setGroup(_ groupId: String) {
    Task(name: "OpenPanel.setGroup") { await shared.setGroup(groupId) }
  }

  /// Attach the current profile to multiple groups at once.
  /// See instance ``setGroups(_:)``.
  static func setGroups(_ groupIds: [String]) {
    Task(name: "OpenPanel.setGroups") { await shared.setGroups(groupIds) }
  }

  /// Increment a numeric profile property. Requires a `profileId`.
  /// See instance ``increment(property:value:profileId:)``.
  static func increment(property: String, value: Double? = nil, profileId: ProfileId? = nil) {
    Task(name: "OpenPanel.increment") {
      await shared.increment(property: property, value: value, profileId: profileId)
    }
  }

  /// Decrement a numeric profile property. Requires a `profileId`.
  /// See instance ``decrement(property:value:profileId:)``.
  static func decrement(property: String, value: Double? = nil, profileId: ProfileId? = nil) {
    Task(name: "OpenPanel.decrement") {
      await shared.decrement(property: property, value: value, profileId: profileId)
    }
  }

  /// Send a `revenue` track event. Reserved keys `__revenue` and
  /// `__deviceId` are added by the SDK.
  /// See instance ``revenue(_:properties:deviceId:)``.
  static func revenue(_ amount: Double, properties: [String: String]? = nil, deviceId: String? = nil) {
    Task(name: "OpenPanel.revenue") { await shared.revenue(amount, properties: properties, deviceId: deviceId) }
  }

  /// Merge `alias` into `profileId` server-side. See instance
  /// ``alias(profileId:alias:)``.
  static func alias(profileId: String, alias: String) {
    Task(name: "OpenPanel.alias") { await shared.alias(profileId: profileId, alias: alias) }
  }

  /// Drain the in-memory queue. No-op while `disabled` or
  /// `waitingForProfile` is set. See instance ``flush()``.
  static func flush() {
    Task(name: "OpenPanel.flush") { await shared.flush() }
  }

  /// Server-issued device identifier, or `nil` until the first successful
  /// response. `async` because reads must hop onto the actor.
  static var deviceId: String? {
    get async { await shared.deviceId }
  }

  /// Server-issued session identifier, or `nil` until the first successful
  /// response. `async` because reads must hop onto the actor.
  static var sessionId: String? {
    get async { await shared.sessionId }
  }
}
